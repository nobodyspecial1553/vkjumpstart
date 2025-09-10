package ns_vkjumpstart_vkjs

@(require) import "core:log"
@(require) import "core:fmt"
import "core:mem"

import vk "vendor:vulkan"

Texture :: struct {
	// Metadata
	using extent: vk.Extent3D, // has 'width', 'height' and 'depth'
	format: vk.Format,
	mip_levels: u32,
	array_layers: u32,
	samples: vk.SampleCountFlags,
	usage: vk.ImageUsageFlags,

	// Data
	image: vk.Image,
	memory: vk.DeviceMemory,
	memory_offset: vk.DeviceSize,
	device_allocator: Device_Allocator,
	/*
		 The 'views' member only exists as a convenience.
		 No "vkjumpstart" procedure will populate it.
		 However, some "vkjumpstart" procedures will do extra things if it is populated.
		 For example, 'texture_destroy' will destroy the 'views'
	*/
	views: []vk.ImageView,
}

@(require_results)
texture_create :: proc(
	device: vk.Device,
	physical_device_memory_properties: vk.PhysicalDeviceMemoryProperties, 
	image_create_info: vk.ImageCreateInfo,
	device_allocator: Device_Allocator,
	image_view_create_infos: []vk.ImageViewCreateInfo = nil,
	image_views_out: []vk.ImageView = nil,
) -> (
	texture: Texture,
	error: Error,
) {
	allocator_error: Allocator_Error
	memory_requirements: vk.MemoryRequirements

	image_create_info := image_create_info

	assert(device != nil)

	// Copy Metadata
	texture.extent = image_create_info.extent
	texture.format = image_create_info.format
	texture.mip_levels = image_create_info.mipLevels
	texture.array_layers = image_create_info.arrayLayers
	texture.samples = image_create_info.samples
	texture.usage = image_create_info.usage
	texture.device_allocator = device_allocator

	// Create the image
	image_create_info.sType = .IMAGE_CREATE_INFO // Don't need to set yourself :)
	error = vk.CreateImage(device, &image_create_info, nil, &texture.image)
	if check_result(error.(vk.Result)) == false {
		log.error("Unable to create image for texture [" + #procedure + "]")
		return {}, error
	}

	// Allocate memory for image
	vk.GetImageMemoryRequirements(device, texture.image, &memory_requirements)
	texture.memory, texture.memory_offset, allocator_error = device_alloc(memory_requirements.size, memory_requirements.alignment, memory_requirements.memoryTypeBits, { .DEVICE_LOCAL }, false, device_allocator)
	switch variant in allocator_error {
	case Device_Allocator_Error:
		vk.DestroyImage(device, texture.image, nil)
		return {}, variant
	case mem.Allocator_Error:
		vk.DestroyImage(device, texture.image, nil)
		return {}, variant
	}

	// Bind memory to image
	error = vk.BindImageMemory(device, texture.image, texture.memory, memoryOffset=texture.memory_offset)
	if check_result(error.(vk.Result)) == false {
		log.error("Unable to bind memory to image for texture! [" + #procedure + "]")
		vk.DestroyImage(device, texture.image, nil)
		device_free(texture.memory, texture.memory_offset, device_allocator)
		return {}, error
	}

	// Create views (if applicable)
	if len(image_views_out) == 0 || len(image_view_create_infos) == 0 { return texture, Device_Allocator_Error.Unknown }

	if len(image_views_out) > len(image_view_create_infos) {
		vk.DestroyImage(device, texture.image, nil)
		device_free(texture.memory, texture.memory_offset, device_allocator)
		return {}, Device_Allocator_Error.Unknown
	}
	for &view, idx in image_views_out {
		image_view_create_info := image_view_create_infos[idx]

		image_view_create_info.sType = .IMAGE_VIEW_CREATE_INFO // Don't need to set yourself :)
		image_view_create_info.image = texture.image
		if vk.CreateImageView(device, &image_view_create_info, nil, &view) != .SUCCESS {
			log.errorf("Unable to create ImageView[%v]", idx)

			texture.views = image_views_out
			texture_destroy(device, texture)

			return texture, Device_Allocator_Error.Unknown
		}
	}

	return texture, nil
}

texture_destroy :: proc(device: vk.Device, texture: Texture) {
	if texture.image != 0 {
		vk.DestroyImage(device, texture.image, nil)
	}
	if texture.views != nil {
		texture_destroy_views(device, texture.views)
	}
	device_free(texture.memory, texture.memory_offset, texture.device_allocator)
}

texture_destroy_views :: proc(device: vk.Device, views: []vk.ImageView) {
	for view in views {
		if view != 0 {
			vk.DestroyImageView(device, view, nil)
		}
	}
}
