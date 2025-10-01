package ns_vkjumpstart_vkjs

@(require) import "core:log"
@(require) import "core:fmt"
import "core:mem"

import vk "vendor:vulkan"

Texture_Metadata :: struct {
	using extent: vk.Extent3D, // has 'width', 'height' and 'depth'
	format: vk.Format,
	mip_levels: u32,
	array_layers: u32,
	samples: vk.SampleCountFlags,
	usage: vk.ImageUsageFlags,
}

Texture :: struct {
	using metadata: Texture_Metadata,

	image: vk.Image,
	memory: vk.DeviceMemory,
	memory_offset: vk.DeviceSize,
	device_allocator: Device_Allocator,
}

@(require_results)
texture_create :: proc(
	device: vk.Device,
	physical_device: vk.PhysicalDevice,
	image_create_info: vk.ImageCreateInfo,
	device_allocator: Device_Allocator,
) -> (
	texture: Texture,
	error: Error,
) {
	allocator_error: Allocator_Error
	memory_requirements: vk.MemoryRequirements
	physical_device_memory_properties: vk.PhysicalDeviceMemoryProperties
	linear_tiling: bool

	image_create_info := image_create_info

	assert(device != nil)

	vk.GetPhysicalDeviceMemoryProperties(physical_device, &physical_device_memory_properties)

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
	if error != nil {
		log.error("Unable to create image for texture [" + #procedure + "]")
		return {}, error
	}

	// Allocate memory for image
	linear_tiling = true if image_create_info.tiling == .LINEAR else false

	vk.GetImageMemoryRequirements(device, texture.image, &memory_requirements)

	texture.memory, texture.memory_offset, _, allocator_error = device_alloc(memory_requirements.size, memory_requirements.alignment, memory_requirements.memoryTypeBits, { .DEVICE_LOCAL }, linear_tiling, device_allocator)
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
	if error != nil {
		log.error("Unable to bind memory to image for texture! [" + #procedure + "]")
		vk.DestroyImage(device, texture.image, nil)
		device_free(texture.memory, texture.memory_offset, device_allocator)
		return {}, error
	}

	return texture, nil
}

texture_destroy :: proc(device: vk.Device, texture: Texture) {
	assert(device != nil)

	if texture.image != 0 {
		vk.DestroyImage(device, texture.image, nil)
	}
	device_free(texture.memory, texture.memory_offset, texture.device_allocator)
}

Texture_View :: struct {
	using metadata: Texture_Metadata,

	handle: vk.ImageView,
}

@(require_results)
texture_view_create :: proc(
	device: vk.Device,
	image_view_create_info: vk.ImageViewCreateInfo,
	texture_metadata: Texture_Metadata = {},
) -> (
	texture_view: Texture_View,
	ok: bool,
) #optional_ok {
	image_view_create_info := image_view_create_info

	assert(device != nil)

	image_view_create_info.sType = .IMAGE_VIEW_CREATE_INFO
	check_result(vk.CreateImageView(device, &image_view_create_info, nil, &texture_view.handle), "Failed to create image view!") or_return

	return texture_view, true
}

texture_view_destroy :: proc(device: vk.Device, texture_view: Texture_View) {
	assert(device != nil)

	vk.DestroyImageView(device, texture_view.handle, nil)
}

find_first_supported_image_format :: proc(physical_device: vk.PhysicalDevice, format_options: []vk.Format, tiling: vk.ImageTiling, features: vk.FormatFeatureFlags) -> (vk.Format, bool) #optional_ok {
	for format in format_options {
		format_properties: vk.FormatProperties = ---
		vk.GetPhysicalDeviceFormatProperties(physical_device, format, &format_properties)

		switch {
		case tiling == .LINEAR && (format_properties.linearTilingFeatures & features) == features:
			return format, true
		case tiling == .OPTIMAL && (format_properties.optimalTilingFeatures & features) == features:
			return format, true
		}
	}

	log.error("Unable to find supported image format!")
	return .UNDEFINED, false
}

format_has_depth_component :: #force_inline proc "contextless" (format: vk.Format) -> (bool) {
	#partial switch format {
	case .D16_UNORM,
			 .X8_D24_UNORM_PACK32,
			 .D32_SFLOAT,
			 .D16_UNORM_S8_UINT,
			 .D24_UNORM_S8_UINT,
			 .D32_SFLOAT_S8_UINT:
		return true
	case:
		return false
	}
}

format_has_stencil_component :: #force_inline proc "contextless" (format: vk.Format) -> (bool) {
	#partial switch format {
	case .D32_SFLOAT_S8_UINT,
			 .D24_UNORM_S8_UINT,
			 .D16_UNORM_S8_UINT,
			 .S8_UINT:
		return true
	case:
		return false
	}
}
