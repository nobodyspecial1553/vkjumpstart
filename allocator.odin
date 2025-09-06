package ns_vkjumpstart_vkjs

@(require) import "core:fmt"
@(require) import "core:log"
import "core:mem"

import vk "vendor:vulkan"

Allocator_Mode :: enum {
	Alloc,
	Free,
	Free_All, // If anyone implements an Arena (or if I do)
	Resize,
}

Allocator_Error :: enum {
	None = 0,
	Unknown,
	Invalid_Pointer,
	Invalid_Argument,
	Out_Of_Device_Memory,
	Out_Of_Host_Memory,
	Mode_Not_Implemented,
}

Allocator_Proc :: #type proc(data: rawptr, mode: Allocator_Mode, size: u32, alignment: u32, memory_type_bits: u32, property_flags: vk.MemoryPropertyFlags, old_memory_offset: u32, old_size: u32, location := #caller_location) -> (memory: vk.DeviceMemory, memory_offset: u32, allocator_error: Allocator_Error)

Allocator :: struct {
	procedure: Allocator_Proc,
	data: rawptr,
}

Heap :: struct {
	device: vk.Device,
	physical_device: vk.PhysicalDevice,
	physical_device_memory_properties: vk.PhysicalDeviceMemoryProperties,
	buffer_image_granularity: vk.DeviceSize,
	max_memory_allocation_count: u32,
	// CPU allocator
	allocator: mem.Allocator,
}

heap_init :: proc(
	heap: ^Heap,
	physical_device: vk.PhysicalDevice,
	device: vk.Device,
	allocator := context.allocator,
) {
	physical_device_properties: vk.PhysicalDeviceProperties

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
}
