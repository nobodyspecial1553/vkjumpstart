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
	Map,
}

Device_Allocator_Error :: enum {
	None = 0,
	Unknown,
	Invalid_Device_Allocator,
	Invalid_Pointer,
	Invalid_Argument,
	No_Valid_Heap,
	Out_Of_Device_Memory,
	Out_Of_Host_Memory,
	Memory_Map_Failed,
	Unmappable_Memory,
	Map_Out_Of_Bounds,
	Bad_Free,
	Mode_Not_Implemented,
}

Allocator_Error :: union #shared_nil {
	Device_Allocator_Error,
	mem.Allocator_Error,
}

Device_Allocator_Proc :: #type proc(data: rawptr, mode: Device_Allocator_Mode, size, alignment: vk.DeviceSize, memory_type_bits: u32, memory_property_flags: vk.MemoryPropertyFlags, is_linear_resource: bool, memory_in: vk.DeviceMemory, memory_offset_in: vk.DeviceSize, location := #caller_location) -> (memory: vk.DeviceMemory, memory_offset: vk.DeviceSize, memory_ptr: rawptr, allocator_error: Allocator_Error)

Device_Allocator :: struct {
	procedure: Device_Allocator_Proc,
	data: rawptr,
}

@(require_results)
device_alloc :: proc(
	size: vk.DeviceSize,
	alignment: vk.DeviceSize,
	memory_type_bits: u32,
	memory_property_flags: vk.MemoryPropertyFlags,
	is_linear_resource: bool,
	device_allocator: Device_Allocator,
	location := #caller_location,
) -> (
	memory: vk.DeviceMemory,
	memory_offset: vk.DeviceSize,
	allocator_error: Allocator_Error,
) {
	assert(size > 0)
	assert(alignment > 0)
	assert(memory_type_bits != 0)
	assert(memory_property_flags != {})

	if device_allocator.procedure == nil {
		return 0, 0, Device_Allocator_Error.Invalid_Device_Allocator
	}
	memory, memory_offset, _, allocator_error = device_allocator.procedure(device_allocator.data, .Alloc, size, alignment, memory_type_bits, memory_property_flags, is_linear_resource, 0, 0, location)
	return
}

device_free :: proc(
	memory: vk.DeviceMemory,
	memory_offset: vk.DeviceSize,
	device_allocator: Device_Allocator,
	location := #caller_location,
) -> (
	allocator_error: Allocator_Error,
) {
	if device_allocator.procedure == nil {
		return Device_Allocator_Error.Invalid_Device_Allocator
	}
	_, _, _, allocator_error = device_allocator.procedure(device_allocator.data, .Free, 0, 0, 0, {}, false, memory, memory_offset, location)
	return allocator_error
}

device_free_all :: proc(
	memory: vk.DeviceMemory,
	device_allocator: Device_Allocator,
	location := #caller_location,
) -> (
	allocator_error: Allocator_Error,
) {
	if device_allocator.procedure == nil {
		return Device_Allocator_Error.Invalid_Device_Allocator
	}
	_, _, _, allocator_error = device_allocator.procedure(device_allocator.data, .Free_All, 0, 0, 0, {}, false, memory, 0, location)
	return allocator_error
}

device_map :: proc(
	memory: vk.DeviceMemory,
	memory_offset: vk.DeviceSize,
	device_allocator: Device_Allocator,
	location := #caller_location,
) -> (
	memory_ptr: rawptr,
	allocator_error: Allocator_Error,
) {
	if device_allocator.procedure == nil {
		return nil, Device_Allocator_Error.Invalid_Device_Allocator
	}
	_, _, memory_ptr, allocator_error = device_allocator.procedure(device_allocator.data, .Map, 0, 0, 0, {}, true, memory, memory_offset, location)
	return
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
	memory_ptr: rawptr, // Only available if memory is HOST_VISIBLE
	size: vk.DeviceSize,
	allocation_array: [dynamic]Heap_Suballocation,
	free_array: [dynamic]Heap_Suballocation,
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
	allocations: map[vk.DeviceMemory]Heap_Allocation,

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
	heap.allocations = make(map[vk.DeviceMemory]Heap_Allocation, 1, heap.allocator) or_return

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

	return .None
}

heap_destroy :: proc(heap: ^Heap) {
	assert(heap != nil)

	for device_memory, heap_allocation in heap.allocations {
		vk.FreeMemory(heap.device, device_memory, nil)
		delete(heap_allocation.allocation_array)
		delete(heap_allocation.free_array)
	}
	delete(heap.allocations)

	heap^ = {}
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
	old_memory: vk.DeviceMemory,
	old_memory_offset: vk.DeviceSize,
	location := #caller_location,
) -> (
	memory: vk.DeviceMemory,
	memory_offset: vk.DeviceSize,
	memory_ptr: rawptr,
	allocator_error: Allocator_Error,
) {
	heap: ^Heap

	assert(data != nil)

	heap = cast(^Heap)data
	context.allocator = heap.allocator

	switch mode {
	case .Alloc:
		alloc_size: vk.DeviceSize
		memory_type_index: u32
		memory_heap_index: u32

		alloc_size = cast(vk.DeviceSize)mem.align_forward_uint(cast(uint)size, HEAP_PAGE_SIZE)
		memory_type_index = get_memory_type_index(memory_type_bits, memory_property_flags, heap.physical_device_memory_properties)
		memory_heap_index = heap.physical_device_memory_properties.memoryTypes[memory_type_index].heapIndex


		if memory_type_index == max(u32) {
			return 0, 0, nil, Device_Allocator_Error.No_Valid_Heap
		}

		for device_memory, &heap_allocation in heap.allocations {
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

				if offset_diff > 0 {
					alignment_free_suballocation: Heap_Suballocation
					alignment_free_suballocation = {
						offset = free_suballocation.offset,
						size = offset_diff,
					}
					append(&heap_allocation.free_array, alignment_free_suballocation) or_return
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

				return device_memory, new_suballocation.offset, nil, nil
			}
		}
		// Could not find any free memory
		{
			heap_allocation: Heap_Allocation
			memory_allocate_info: vk.MemoryAllocateInfo
			memory_allocate_flags_info: vk.MemoryAllocateFlagsInfo
			suballocation: Heap_Suballocation
			free_suballocation: Heap_Suballocation

			heap_allocation = {
				size = cast(vk.DeviceSize)mem.align_forward_uint(cast(uint)size, HEAP_PAGE_SIZE),
			}
			heap_allocation.allocation_array = make([dynamic]Heap_Suballocation, 0, 32, heap.allocator)
			heap_allocation.free_array = make([dynamic]Heap_Suballocation, 0, 32, heap.allocator)

			if is_linear_resource {
				heap_allocation.property_flags += { .Linear_Resources }
			}

			memory_allocate_flags_info = {
				sType = .MEMORY_ALLOCATE_FLAGS_INFO,
				flags = { .DEVICE_ADDRESS },
			}
			memory_allocate_info = {
				sType = .MEMORY_ALLOCATE_INFO,
				pNext = &memory_allocate_flags_info,
				allocationSize = alloc_size,
				memoryTypeIndex = memory_type_index,
			}
			#partial switch vk_alloc_error := vk.AllocateMemory(heap.device, &memory_allocate_info, nil, &memory); vk_alloc_error {
			case .SUCCESS:
				break
			case .ERROR_OUT_OF_DEVICE_MEMORY:
				return 0, 0, nil, Device_Allocator_Error.Out_Of_Device_Memory
			case .ERROR_OUT_OF_HOST_MEMORY:
				return 0, 0, nil, Device_Allocator_Error.Out_Of_Host_Memory
			case:
				return 0, 0, nil, Device_Allocator_Error.Unknown
			}

			if .HOST_VISIBLE in memory_property_flags {
				#partial switch vk_map_error := vk.MapMemory(heap.device, memory, 0, cast(vk.DeviceSize)vk.WHOLE_SIZE, {}, &heap_allocation.memory_ptr); vk_map_error {
				case .SUCCESS:
					break
				case .ERROR_MEMORY_MAP_FAILED:
					vk.FreeMemory(heap.device, memory, nil)
					return 0, 0, nil, Device_Allocator_Error.Memory_Map_Failed
				case .ERROR_OUT_OF_DEVICE_MEMORY:
					vk.FreeMemory(heap.device, memory, nil)
					return 0, 0, nil, Device_Allocator_Error.Out_Of_Device_Memory
				case .ERROR_OUT_OF_HOST_MEMORY:
					vk.FreeMemory(heap.device, memory, nil)
					return 0, 0, nil, Device_Allocator_Error.Out_Of_Host_Memory
				case:
					vk.FreeMemory(heap.device, memory, nil)
					return 0, 0, nil, Device_Allocator_Error.Unknown
				}
				heap_allocation.property_flags += { .Is_Mapped }
			}

			suballocation = {
				offset = 0,
				size = size,
			}
			if append_count := append(&heap_allocation.allocation_array, suballocation); append_count == 0 {
				vk.FreeMemory(heap.device, memory, nil)
				return 0, 0, nil, mem.Allocator_Error.Out_Of_Memory
			}

			free_suballocation = {
				offset = size,
				size = alloc_size - size,
			}
			if append_count := append(&heap_allocation.free_array, free_suballocation); append_count == 0 {
				vk.FreeMemory(heap.device, memory, nil)
				pop(&heap_allocation.allocation_array)
				return 0, 0, nil, mem.Allocator_Error.Out_Of_Memory
			}

			heap.allocations[memory] = heap_allocation
			{
				// Is this a good way to check?
				allocations_map_append_ok: bool
				allocations_map_append_ok = memory in heap.allocations
				if allocations_map_append_ok == false {
					vk.FreeMemory(heap.device, memory, nil)
					return 0, 0, nil, mem.Allocator_Error.Out_Of_Memory
				}
			}

			return memory, suballocation.offset, nil, nil
		}
	case .Free:
		heap_allocation: Heap_Allocation
		heap_allocation_exists: bool

		allocation: Heap_Suballocation
		free_allocation: Heap_Suballocation

		heap_allocation, heap_allocation_exists = heap.allocations[old_memory]
		if heap_allocation_exists == false {
			return 0, 0, nil, Device_Allocator_Error.Bad_Free
		}

		for _allocation, _allocation_index in heap_allocation.allocation_array {
			if old_memory_offset == _allocation.offset {
				allocation = _allocation
				unordered_remove(&heap_allocation.allocation_array, _allocation_index)
				break
			}
		}
		if allocation.size == 0 {
			return 0, 0, nil, Device_Allocator_Error.Bad_Free
		}

		free_allocation = allocation

		for i := 0; i < len(heap_allocation.free_array); i += 1 {
			_free_allocation: ^Heap_Suballocation

			#no_bounds_check _free_allocation = &heap_allocation.free_array[i]

			if _free_allocation.offset + _free_allocation.size == free_allocation.offset {
				free_allocation.offset = _free_allocation.offset
				free_allocation.size += _free_allocation.size

				unordered_remove(&heap_allocation.free_array, i)

				i -= 1
				continue
			}

			if _free_allocation.offset == free_allocation.offset + free_allocation.size {
				free_allocation.size += _free_allocation.size

				unordered_remove(&heap_allocation.free_array, i)

				break
			}
		}

		if len(heap_allocation.allocation_array) == 0 {
			delete(heap_allocation.allocation_array)
			delete(heap_allocation.free_array)
			vk.FreeMemory(heap.device, old_memory, nil)
			delete_key(&heap.allocations, old_memory)
		}
		else {
			append(&heap_allocation.free_array, free_allocation) or_return
		}

		return 0, 0, nil, nil
	case .Free_All:
		return 0, 0, nil, Device_Allocator_Error.Mode_Not_Implemented
	case .Map:
		heap_allocation: Heap_Allocation
		heap_allocation_found: bool

		heap_allocation, heap_allocation_found = heap.allocations[old_memory]
		if heap_allocation_found == false {
			return 0, 0, nil, Device_Allocator_Error.Invalid_Argument
		}

		if .Is_Mapped not_in heap_allocation.property_flags {
			return 0, 0, nil, Device_Allocator_Error.Unmappable_Memory
		}

		if old_memory_offset >= heap_allocation.size {
			return 0, 0, nil, Device_Allocator_Error.Map_Out_Of_Bounds
		}

		return old_memory, old_memory_offset, (cast([^]byte)heap_allocation.memory_ptr)[old_memory_offset:], nil
	}

	return 0, 0, nil, Device_Allocator_Error.Unknown
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
