package ns_vkjumpstart_vkjs

@(require) import "core:fmt"
@(require) import "core:log"
import "core:mem"

import vk "vendor:vulkan"

Buffer :: struct {
	handle: vk.Buffer,
	size: vk.DeviceSize,
	memory: vk.DeviceMemory,
	memory_size: vk.DeviceSize,
	memory_offset: vk.DeviceSize,
	address: vk.DeviceAddress,
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

	physical_device_memory_properties: vk.PhysicalDeviceMemoryProperties

	buffer_create_info := buffer_create_info

	assert(len(buffer_array_out) > 0)

	vk.GetPhysicalDeviceMemoryProperties(physical_device, &physical_device_memory_properties)

	buffer_create_info.sType = .BUFFER_CREATE_INFO
	for &buffer, idx in buffer_array_out {
		// Create buffers
		create_buffer_error: vk.Result

		device_allocator_error: Allocator_Error
		memory_requirements: vk.MemoryRequirements

		bind_buffer_memory_error: vk.Result

		create_buffer_error = vk.CreateBuffer(device, &buffer_create_info, nil, &buffer.handle)

		if check_result(create_buffer_error) == false {
			log.errorf("Failed to create buffer '%v' [" + #procedure + "]", idx)
			destroy_buffers(device, buffer_array_out, idx)
			return create_buffer_error
		}

		buffer.size = buffer_create_info.size
		buffer.device_allocator = device_allocator

		// Allocate Memory
		vk.GetBufferMemoryRequirements(device, buffer.handle, &memory_requirements)

		buffer.memory, buffer.memory_offset, buffer.memory_size, device_allocator_error = device_alloc(memory_requirements.size, memory_requirements.alignment, memory_requirements.memoryTypeBits, memory_property_flags, true, device_allocator)
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

		// Bind buffer to memory
		bind_buffer_memory_error = vk.BindBufferMemory(device, buffer.handle, buffer.memory, memoryOffset = buffer.memory_offset)
		if check_result(bind_buffer_memory_error) == false {
			log.errorf("Failed to bind buffer '%v' to memory!", idx)

			device_free(buffer.memory, buffer.memory_offset, buffer.device_allocator)
			destroy_buffers(device, buffer_array_out)

			return bind_buffer_memory_error
		}

		if .SHADER_DEVICE_ADDRESS in buffer_create_info.usage {
			buffer_device_address_info: vk.BufferDeviceAddressInfo

			buffer_device_address_info = {
				sType = .BUFFER_DEVICE_ADDRESS_INFO_EXT,
				buffer = buffer.handle,
			}
			buffer.address = vk.GetBufferDeviceAddress(device, &buffer_device_address_info)
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
