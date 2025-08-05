package ns_vkjumpstart_vkjs

import "core:log"
import "core:fmt"
import "core:mem"
import "core:slice"

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
	/*
		 The 'views' member only exists as a convenience.
		 No "vkjumpstart" procedure will populate it.
		 However, some "vkjumpstart" procedures will do extra things if it is populated.
		 For example, 'texture_destroy' will destroy the 'views'
	*/
	views: []vk.ImageView,
}

@(require_results)
texture_create :: proc
(
	device: vk.Device,
	physical_device_memory_properties: vk.PhysicalDeviceMemoryProperties, 
	image_create_info: vk.ImageCreateInfo,
	image_view_create_infos: []vk.ImageViewCreateInfo = nil,
	image_views_out: []vk.ImageView = nil,
) -> (
	texture: Texture,
	ok: bool,
) #optional_ok {
	image_create_info := image_create_info

	memory_requirements: vk.MemoryRequirements
	memory_type_index: u32
	memory_allocate_info: vk.MemoryAllocateInfo

	assert(device != nil)

	// Copy Metadata
	texture.extent = image_create_info.extent
	texture.format = image_create_info.format
	texture.mip_levels = image_create_info.mipLevels
	texture.array_layers = image_create_info.arrayLayers
	texture.samples = image_create_info.samples
	texture.usage = image_create_info.usage

	// Create the image
	image_create_info.sType = .IMAGE_CREATE_INFO // Don't need to set yourself :)
	check_result(vk.CreateImage(device, &image_create_info, nil, &texture.image), "Unable to create image for texture! [" + #procedure + "]") or_return

	// Allocate memory for image
	vk.GetImageMemoryRequirements(device, texture.image, &memory_requirements)
	memory_type_index = get_memory_type_index(memory_requirements.memoryTypeBits, { .DEVICE_LOCAL }, physical_device_memory_properties)
	if memory_type_index == max(u32) {
		log.error("Failed to find valid memory heap! [" + #procedure + "]")
		return texture, false
	}

	memory_allocate_info = vk.MemoryAllocateInfo {
		sType = .MEMORY_ALLOCATE_INFO,
		allocationSize = memory_requirements.size,
		memoryTypeIndex = memory_type_index,
	}
	check_result(vk.AllocateMemory(device, &memory_allocate_info, nil, &texture.memory), "Unable to allocate memory for texture! [" + #procedure + "]") or_return

	// Bind memory to image
	check_result(vk.BindImageMemory(device, texture.image, texture.memory, memoryOffset=0), "Unable to bind memory to image for texture! [" + #procedure + "]") or_return

	// Create views (if applicable)
	if len(image_views_out) == 0 || len(image_view_create_infos) == 0 { return texture, true }

	assert(len(image_views_out) == len(image_view_create_infos))
	ensure(len(image_views_out) <= len(image_view_create_infos))
	for &view, idx in image_views_out {
		image_view_create_info := image_view_create_infos[idx]

		image_view_create_info.sType = .IMAGE_VIEW_CREATE_INFO // Don't need to set yourself :)
		image_view_create_info.image = texture.image
		if vk.CreateImageView(device, &image_view_create_info, nil, &view) != .SUCCESS {
			log.errorf("Unable to create ImageView[%v]", idx)

			texture.views = image_views_out
			texture_destroy(device, texture)

			return texture, false
		}
	}

	return texture, true
}

texture_destroy :: proc(device: vk.Device, texture: Texture) {
	if texture.image != 0 {
		vk.DestroyImage(device, texture.image, nil)
	}
	if texture.memory != 0 {
		vk.FreeMemory(device, texture.memory, nil)
	}
	if texture.views != nil {
		texture_destroy_views(device, texture.views)
	}
}

texture_destroy_views :: proc(device: vk.Device, views: []vk.ImageView) {
	for view in views {
		if view != 0 {
			vk.DestroyImageView(device, view, nil)
		}
	}
}
