package ns_vkjumpstart_vkjs

@(require) import "core:fmt"
@(require) import "core:log"
import "core:mem"

import vk "vendor:vulkan"

Device_Allocator_Mode :: enum {
	Alloc,
	Free,
	Free_All, // If anyone implements an Arena (or if I do)
	Resize,
}

Device_Allocator_Error :: enum {
	None = 0,
	Unknown,
	Invalid_Pointer,
	Invalid_Argument,
	No_Valid_Heap,
	Out_Of_Device_Memory,
	Out_Of_Host_Memory,
	Mode_Not_Implemented,
}

Allocator_Error :: union #shared_nil {
	Device_Allocator_Error,
	mem.Allocator_Error,
}

Device_Allocator_Proc :: #type proc(data: rawptr, mode: Device_Allocator_Mode, size, alignment: vk.DeviceSize, memory_type_bits: u32, property_flags: vk.MemoryPropertyFlags, old_memory_offset, old_size: vk.DeviceSize, location := #caller_location) -> (memory: vk.DeviceMemory, memory_offset: vk.DeviceSize, allocator_error: Allocator_Error)

Device_Allocator :: struct {
	procedure: Device_Allocator_Proc,
	data: rawptr,
}

Heap_Suballocation :: struct {
	offset: vk.DeviceSize,
	size: vk.DeviceSize,
}

Heap_Allocation :: struct {
	memory: vk.DeviceMemory,
	size: vk.DeviceSize,
	allocation_array: [dynamic]Heap_Suballocation,
	free_array: [dynamic]Heap_Suballocation,
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

heap_allocator_procedure : Device_Allocator_Proc : proc(
	data: rawptr,
	mode: Device_Allocator_Mode,
	size: vk.DeviceSize,
	alignment: vk.DeviceSize,
	memory_type_bits: u32,
	property_flags: vk.MemoryPropertyFlags,
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

	assert(data != nil)

	heap = cast(^Heap)data
	context.allocator = heap.allocator

	memory_type_index = get_memory_type_index(memory_type_bits, property_flags, heap.physical_device_memory_properties)
	memory_heap_index = heap.physical_device_memory_properties.memoryTypes[memory_type_index].heapIndex

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
