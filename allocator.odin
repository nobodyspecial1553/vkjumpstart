package ns_vkjumpstart_vkjs

@(require) import "core:fmt"
@(require) import "core:log"
import "core:mem"

import vk "vendor:vulkan"

Device_Allocator_Mode :: enum {
	Alloc,
	Free,
	Free_All, // If anyone implements an Arena (or if I do)
	// Resize, // No reasonable way to copy agnostically (THAT I KNOW OF! LOL)
}

Device_Allocator_Error :: enum {
	None = 0,
	Unknown,
	Invalid_Pointer,
	Invalid_Argument,
	No_Valid_Heap,
	Out_Of_Device_Memory,
	Out_Of_Host_Memory,
	Memory_Map_Failed,
	Mode_Not_Implemented,
}

Allocator_Error :: union #shared_nil {
	Device_Allocator_Error,
	mem.Allocator_Error,
}

Device_Allocator_Proc :: #type proc(data: rawptr, mode: Device_Allocator_Mode, size, alignment: vk.DeviceSize, memory_type_bits: u32, memory_property_flags: vk.MemoryPropertyFlags, is_linear_resource: bool, old_memory_offset, old_size: vk.DeviceSize, location := #caller_location) -> (memory: vk.DeviceMemory, memory_offset: vk.DeviceSize, allocator_error: Allocator_Error)

Device_Allocator :: struct {
	procedure: Device_Allocator_Proc,
	data: rawptr,
}

Heap_Suballocation :: struct {
	offset: vk.DeviceSize,
	size: vk.DeviceSize,
}

Heap_Allocation_Property_Flags :: bit_set[Heap_Allocation_Property_Flag]
Heap_Allocation_Property_Flag :: enum {
	Linear_Resources, // To separate linear and non-linear allocations entirely
	Is_Mapped,
}

Heap_Allocation :: struct {
	memory: vk.DeviceMemory,
	memory_ptr: rawptr, // Only available if memory is HOST_VISIBLE
	size: vk.DeviceSize,
	allocation_array: [dynamic]Heap_Suballocation,
	free_array: [dynamic]Heap_Suballocation, // Should be ordered smallest to biggest
	property_flags: Heap_Allocation_Property_Flags,
}

Heap :: struct {
	device: vk.Device,
	physical_device: vk.PhysicalDevice,

	// Properties
	physical_device_memory_properties: vk.PhysicalDeviceMemoryProperties,
	buffer_image_granularity: vk.DeviceSize,

	// GPU Allocator
	max_memory_allocation_count: u32,
	allocations: u32,
	heap_allocations: [/*heaps*/][dynamic]Heap_Allocation,

	// CPU allocator
	allocator: mem.Allocator,
}

heap_allocator :: proc(heap: ^Heap) -> Device_Allocator {
	return Device_Allocator {
		data = heap,
		procedure = heap_allocator_procedure,
	}
}

heap_init :: proc(
	heap: ^Heap,
	physical_device: vk.PhysicalDevice,
	device: vk.Device,
	allocator := context.allocator,
) -> (
	allocator_error: mem.Allocator_Error,
) {
	physical_device_properties: vk.PhysicalDeviceProperties

	context.allocator = allocator

	assert(heap != nil)
	assert(physical_device != nil)
	assert(device != nil)

	vk.GetPhysicalDeviceProperties(physical_device, &physical_device_properties)
	vk.GetPhysicalDeviceMemoryProperties(physical_device, &heap.physical_device_memory_properties)

	heap.allocator = allocator
	heap.device = device
	heap.physical_device = physical_device
	heap.buffer_image_granularity = physical_device_properties.limits.bufferImageGranularity
	heap.max_memory_allocation_count = physical_device_properties.limits.maxMemoryAllocationCount

	log.infof("Buffer Image Granularity: %v", heap.buffer_image_granularity)
	log.infof("Max Memory Allocation Count: %v", heap.max_memory_allocation_count)

	log.infof("Memory Heap Count: %v", heap.physical_device_memory_properties.memoryHeapCount)
	for memory_heap, index in heap.physical_device_memory_properties.memoryHeaps[:heap.physical_device_memory_properties.memoryHeapCount] {
		log.infof("Memory Heap %v - Size: %v; Flags: %v", index, memory_heap.size, memory_heap.flags)
	}

	log.infof("Memory Type Count: %v", heap.physical_device_memory_properties.memoryTypeCount)
	for memory_type, index in heap.physical_device_memory_properties.memoryTypes[:heap.physical_device_memory_properties.memoryTypeCount] {
		log.infof("Memory Type %v - Heap index: %v; Property Flags: %v", index, memory_type.heapIndex, memory_type.propertyFlags)
	}

	heap.heap_allocations = make([][dynamic]Heap_Allocation, 2, allocator) or_return
	for &heap_allocation in heap.heap_allocations {
		heap_allocation = make([dynamic]Heap_Allocation, 0, 32, allocator) or_return
	}

	return .None
}

@(private="file")
HEAP_PAGE_SIZE :: #config(VKJS_HEAP_PAGE_SIZE, mem.Megabyte * 128)

heap_allocator_procedure : Device_Allocator_Proc : proc(
	data: rawptr,
	mode: Device_Allocator_Mode,
	size: vk.DeviceSize,
	alignment: vk.DeviceSize,
	memory_type_bits: u32,
	memory_property_flags: vk.MemoryPropertyFlags,
	is_linear_resource: bool,
	old_memory_offset: vk.DeviceSize,
	old_size: vk.DeviceSize,
	location := #caller_location,
) -> (
	memory: vk.DeviceMemory,
	memory_offset: vk.DeviceSize,
	allocator_error: Allocator_Error,
) {
	heap: ^Heap
	memory_type_index: u32
	memory_heap_index: u32
	alloc_size: vk.DeviceSize

	assert(data != nil)

	heap = cast(^Heap)data
	context.allocator = heap.allocator

	memory_type_index = get_memory_type_index(memory_type_bits, memory_property_flags, heap.physical_device_memory_properties)
	memory_heap_index = heap.physical_device_memory_properties.memoryTypes[memory_type_index].heapIndex
	alloc_size = cast(vk.DeviceSize)mem.align_forward_uint(cast(uint)size, HEAP_PAGE_SIZE)

	switch mode {
	case .Alloc:
		if memory_type_index == max(u32) {
			return 0, 0, Device_Allocator_Error.No_Valid_Heap
		}

		for &heap_allocation in heap.heap_allocations[memory_heap_index] {
			switch {
			case size > heap_allocation.size:
				continue
			case is_linear_resource && .Linear_Resources not_in heap_allocation.property_flags:
				continue
			case !is_linear_resource && .Linear_Resources in heap_allocation.property_flags:
				continue
			}
			
			for &free_suballocation, free_suballocation_index in heap_allocation.free_array {
				new_suballocation: Heap_Suballocation
				offset_aligned: vk.DeviceSize
				offset_diff: vk.DeviceSize
				size_aligned: vk.DeviceSize // Shrunk from alignment

				offset_aligned = cast(vk.DeviceSize)mem.align_forward_uint(cast(uint)free_suballocation.offset, cast(uint)alignment)
				offset_diff = offset_aligned - free_suballocation.offset
				size_aligned = free_suballocation.size - offset_diff

				if size > size_aligned {
					continue
				}

				free_suballocation.offset = offset_aligned + size
				free_suballocation.size -= size + offset_diff
				if free_suballocation.size == 0 {
					unordered_remove(&heap_allocation.free_array, free_suballocation_index)
				}

				new_suballocation = {
					offset = offset_aligned,
					size = size,
				}
				append(&heap_allocation.allocation_array, new_suballocation) or_return

				return heap_allocation.memory, new_suballocation.offset, nil
			}
		}
		// Could not find any free memory
		{
			heap_allocation: Heap_Allocation
			memory_allocate_info: vk.MemoryAllocateInfo
			suballocation: Heap_Suballocation
			free_suballocation: Heap_Suballocation

			heap_allocation = {
				size = cast(vk.DeviceSize)mem.align_forward_uint(cast(uint)size, HEAP_PAGE_SIZE),
			}
			heap_allocation.allocation_array.allocator = context.allocator
			heap_allocation.free_array.allocator = context.allocator

			if is_linear_resource {
				heap_allocation.property_flags += { .Linear_Resources }
			}

			memory_allocate_info = {
				sType = .MEMORY_ALLOCATE_INFO,
				allocationSize = alloc_size,
				memoryTypeIndex = memory_type_index,
			}
			#partial switch vk_alloc_error := vk.AllocateMemory(heap.device, &memory_allocate_info, nil, &heap_allocation.memory); vk_alloc_error {
			case .SUCCESS:
				break
			case .ERROR_OUT_OF_DEVICE_MEMORY:
				return 0, 0, Device_Allocator_Error.Out_Of_Device_Memory
			case .ERROR_OUT_OF_HOST_MEMORY:
				return 0, 0, Device_Allocator_Error.Out_Of_Host_Memory
			case:
				return 0, 0, Device_Allocator_Error.Unknown
			}

			if .HOST_VISIBLE in memory_property_flags {
				#partial switch vk_map_error := vk.MapMemory(heap.device, heap_allocation.memory, 0, cast(vk.DeviceSize)vk.WHOLE_SIZE, {}, &heap_allocation.memory_ptr); vk_map_error {
				case .SUCCESS:
					break
				case .ERROR_MEMORY_MAP_FAILED:
					vk.FreeMemory(heap.device, heap_allocation.memory, nil)
					return 0, 0, Device_Allocator_Error.Memory_Map_Failed
				case .ERROR_OUT_OF_DEVICE_MEMORY:
					vk.FreeMemory(heap.device, heap_allocation.memory, nil)
					return 0, 0, Device_Allocator_Error.Out_Of_Device_Memory
				case .ERROR_OUT_OF_HOST_MEMORY:
					vk.FreeMemory(heap.device, heap_allocation.memory, nil)
					return 0, 0, Device_Allocator_Error.Out_Of_Host_Memory
				case:
					vk.FreeMemory(heap.device, heap_allocation.memory, nil)
					return 0, 0, Device_Allocator_Error.Unknown
				}
				heap_allocation.property_flags += { .Is_Mapped }
			}

			append(&heap.heap_allocations[memory_heap_index], heap_allocation) or_return

			suballocation = {
				offset = 0,
				size = size,
			}
			append(&heap.heap_allocations[memory_heap_index][len(heap.heap_allocations[memory_heap_index]) - 1].allocation_array, suballocation) or_return

			free_suballocation = {
				offset = size,
				size = alloc_size - size,
			}
			append(&heap.heap_allocations[memory_heap_index][len(heap.heap_allocations[memory_heap_index]) - 1].free_array, free_suballocation) or_return

			return heap_allocation.memory, suballocation.offset, nil
		}
	case .Free:
	case .Free_All:
		return 0, 0, Device_Allocator_Error.Mode_Not_Implemented
	}

	return 0, 0, Device_Allocator_Error.Unknown
}

get_memory_type_index :: proc(memory_type_bits: u32, requested_properties: vk.MemoryPropertyFlags, physical_device_memory_properties: vk.PhysicalDeviceMemoryProperties) -> (u32, bool) #optional_ok {
	memory_type_bits := memory_type_bits
	for index in u32(0)..<physical_device_memory_properties.memoryTypeCount {
		if (memory_type_bits & 1) == 1 && (physical_device_memory_properties.memoryTypes[index].propertyFlags & requested_properties) == requested_properties {
			return index, true
		}
		memory_type_bits >>= 1
	}
	return max(u32), false
}
