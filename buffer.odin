package ns_vkjumpstart_vkjs

import "base:runtime"

@(require) import "core:fmt"
@(require) import "core:log"
import "core:mem"

import vk "vendor:vulkan"

Buffer :: struct {
	handle: vk.Buffer,
	memory: vk.DeviceMemory,
	memory_offset: vk.DeviceSize,
	device_allocator: Device_Allocator,
}

@(require_results)
buffer_create :: proc(
	device: vk.Device,
	physical_device: vk.PhysicalDevice,
	buffer_create_info: vk.BufferCreateInfo,
	memory_property_flags: vk.MemoryPropertyFlags,
	buffer_array_out: []Buffer,
	device_allocator: Device_Allocator,
) -> (
	error: Error,
) {
	destroy_buffers :: proc(device: vk.Device, buffer_array: []Buffer, #any_int end := max(int)) {
		for buffer, idx in buffer_array {
			if idx == end { break }
			vk.DestroyBuffer(device, buffer.handle, nil)
		}
	}

	device_memory: vk.DeviceMemory
	device_memory_offset: vk.DeviceSize
	memory_requirements: vk.MemoryRequirements
	physical_device_memory_properties: vk.PhysicalDeviceMemoryProperties

	buffer_create_info := buffer_create_info

	assert(len(buffer_array_out) > 0)

	vk.GetPhysicalDeviceMemoryProperties(physical_device, &physical_device_memory_properties)

	// Create buffers
	buffer_create_info.sType = .BUFFER_CREATE_INFO
	#no_bounds_check for &buffer_out, idx in buffer_array_out {
		create_buffer_error: vk.Result

		create_buffer_error = vk.CreateBuffer(device, &buffer_create_info, nil, &buffer_out.handle)

		if check_result(vk.CreateBuffer(device, &buffer_create_info, nil, &buffer_out.handle)) == false {
			log.errorf("Failed to create buffer '%v' [" + #procedure + "]", idx)
			destroy_buffers(device, buffer_array_out, idx)
			return create_buffer_error
		}

		buffer_out.device_allocator = device_allocator
	}

	// Allocate Memory
	{
		memory_alloc_size: vk.DeviceSize
		device_allocator_error: Allocator_Error

		vk.GetBufferMemoryRequirements(device, buffer_array_out[0].handle, &memory_requirements)

		memory_alloc_size = memory_requirements.size
		memory_alloc_size = cast(vk.DeviceSize)runtime.align_forward_uint(cast(uint)memory_alloc_size, cast(uint)memory_requirements.alignment)
		memory_alloc_size *= cast(vk.DeviceSize)len(buffer_array_out)

		device_memory, device_memory_offset, device_allocator_error = device_alloc(memory_alloc_size, memory_requirements.alignment, memory_requirements.memoryTypeBits, memory_property_flags, true, device_allocator)
		if device_allocator_error != nil {
			log.errorf("Buffer memory allocator error: %v", device_allocator_error)
			destroy_buffers(device, buffer_array_out)

			switch variant in device_allocator_error {
			case Device_Allocator_Error:
				return variant
			case mem.Allocator_Error:
				return variant
			}
		}
	}

	// Bind buffers to memory
	{
		buffer_offset: vk.DeviceSize

		buffer_offset = device_memory_offset

		for &buffer, idx in buffer_array_out {
			bind_buffer_memory_error: vk.Result

			buffer.memory = device_memory
			buffer.memory_offset = buffer_offset

			bind_buffer_memory_error = vk.BindBufferMemory(device, buffer.handle, device_memory, memoryOffset = buffer_offset)
			if check_result(bind_buffer_memory_error) == false {
				log.errorf("Failed to bind buffer '%v' to memory!", idx)

				vk.FreeMemory(device, device_memory, nil)
				destroy_buffers(device, buffer_array_out)

				return bind_buffer_memory_error
			}
			buffer_offset += memory_requirements.size
			buffer_offset += cast(vk.DeviceSize)runtime.align_forward_uint(cast(uint)buffer_offset, cast(uint)memory_requirements.alignment)
		}
	}

	return nil
}

buffer_destroy :: proc(device: vk.Device, buffer: Buffer) {
	assert(device != nil)

	if buffer.handle != 0 {
		vk.DestroyBuffer(device, buffer.handle, nil)
	}
	device_free(buffer.memory, buffer.memory_offset, buffer.device_allocator)
}
