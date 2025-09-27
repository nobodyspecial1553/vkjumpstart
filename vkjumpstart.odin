package ns_vkjumpstart_vkjs

import "base:intrinsics"

@(require) import "core:fmt"
@(require) import "core:log"
import "core:mem"
import "core:dynlib"
import "core:strings"

import vk "vendor:vulkan"
import "vendor:glfw"

when ODIN_OS == .Linux {
	VULKAN_LIB_PATH :: "libvulkan.so.1"
}
else when ODIN_OS == .Windows {
	VULKAN_LIB_PATH :: "vulkan-1.dll"
}
else when ODIN_OS == .Darwin {
	// VULKAN_LIB_PATH :: "libvulkan.1.dylib"
	#panic("vkjumpstart: Unsupported OS!")
}
else {
	#panic("vkjumpstart: Unsupported OS!")
}

@(private)
ENABLE_DEBUG_FEATURES :: #config(VKJS_ENABLE_DEBUG_FEATURES, ODIN_DEBUG)

@(require_results)
version_extract_major_minor_patch :: proc "contextless" (version: u32) -> (major: u32, minor: u32, patch: u32) {
	return version >> 22, (version >> 12) & 0x3FF, version & 0xFFF
}

@(require_results)
load_vulkan :: proc() -> (vulkan_lib: dynlib.Library, vkGetInstanceProcAddr: rawptr, ok: bool) {
	vkGetInstanceProcAddr_Str :: "vkGetInstanceProcAddr"

	vulkan_lib, ok = dynlib.load_library(VULKAN_LIB_PATH)
	if !ok {
		log.fatal("Unable to load vulkan library: \"%s\"", VULKAN_LIB_PATH)
		return {}, nil, false
	}

	vkGetInstanceProcAddr, ok = dynlib.symbol_address(vulkan_lib, vkGetInstanceProcAddr_Str)
	if !ok {
		log.fatal("Unable to find symbol address: " + vkGetInstanceProcAddr_Str)
		dynlib.unload_library(vulkan_lib) or_return
		return {}, nil, false
	}

	return vulkan_lib, vkGetInstanceProcAddr, ok
}

unload_vulkan :: proc(vulkan_lib: dynlib.Library) -> (ok: bool) {
	return dynlib.unload_library(vulkan_lib)
}

@(require_results)
instance_create :: proc(
	vkGetInstanceProcAddr_func: rawptr,
	instance_extension_array: []cstring,
	application_name: cstring = "",
	application_version: u32 = 0,
	engine_name: cstring = "",
	engine_version: u32 = 0,
	api_version_target: u32 = 0,
	enable_debug_features: bool = ENABLE_DEBUG_FEATURES,
	temp_allocator := context.temp_allocator,
) -> (
	instance: vk.Instance,
	ok: bool,
) #optional_ok {
	api_version: u32
	instance_extension_properties_array: []vk.ExtensionProperties

	application_info: vk.ApplicationInfo
	instance_create_info: vk.InstanceCreateInfo
	instance_create_result: vk.Result

	assert(vkGetInstanceProcAddr_func != nil)

	context.temp_allocator = temp_allocator

	vk.load_proc_addresses_global(vkGetInstanceProcAddr_func)

	check_result(vk.EnumerateInstanceVersion(&api_version), "Unable to get Instance API Version!") or_return
	{
		major, minor, patch := version_extract_major_minor_patch(api_version)
		log.infof("Vulkan Instance API Version: %v.%v.%v", major, minor, patch)
	}

	{
		instance_extension_properties_count: u32
		vk.EnumerateInstanceExtensionProperties(nil, &instance_extension_properties_count, nil)
		instance_extension_properties_array = make([]vk.ExtensionProperties, instance_extension_properties_count, context.temp_allocator)
		vk.EnumerateInstanceExtensionProperties(nil, &instance_extension_properties_count, raw_data(instance_extension_properties_array))
	}

	instance_extension_match_found: for required_instance_extension in instance_extension_array {
		for &instance_extension_properties in instance_extension_properties_array {
			extension_name: cstring
			extension_name = cstring(raw_data(&instance_extension_properties.extensionName))
			if required_instance_extension == extension_name {
				log.infof("Enabling Instance Extension: \"%s\"", extension_name)
				continue instance_extension_match_found
			}
		}
		log.errorf("Instance Extension \"%s\" is not supported!", required_instance_extension)
		return instance, false
	}

	application_info = vk.ApplicationInfo {
		sType = .APPLICATION_INFO,
		pApplicationName = application_name,
		applicationVersion = application_version,
		pEngineName = engine_name,
		engineVersion = engine_version,
		apiVersion = api_version if api_version_target == 0 else api_version_target,
	}
	{
		major, minor, patch := version_extract_major_minor_patch(application_info.apiVersion)
		log.infof("Selected Instance API Version: %v.%v.%v", major, minor, patch)
	}

	instance_create_info = vk.InstanceCreateInfo {
		sType = .INSTANCE_CREATE_INFO,
		flags = { /* .ENUMERATE_PORTABILITY_KKHR */ },
		pApplicationInfo = &application_info,
		enabledExtensionCount = cast(u32)len(instance_extension_array),
		ppEnabledExtensionNames = raw_data(instance_extension_array),
	}

	if enable_debug_features {
		@(static, rodata)
		instance_layer_property_array := [?]cstring {
			"VK_LAYER_KHRONOS_validation",
		}
		validation_features_enable_array := [?]vk.ValidationFeatureEnableEXT {
			.BEST_PRACTICES,
			/*.GPU_ASSISTED,*/
			.SYNCHRONIZATION_VALIDATION,
		}

		validation_features: vk.ValidationFeaturesEXT

		layer_properties_array: []vk.LayerProperties
		layer_properties_count: u32

		vk.EnumerateInstanceLayerProperties(&layer_properties_count, nil)
		layer_properties_array = make([]vk.LayerProperties, layer_properties_count, context.temp_allocator)
		vk.EnumerateInstanceLayerProperties(&layer_properties_count, raw_data(layer_properties_array))

		instance_layer_property_match_found: for required_layer_property in instance_layer_property_array {
			for &layer_properties in layer_properties_array {
				layer_name: cstring
				layer_name = cstring(raw_data(&layer_properties.layerName))
				if required_layer_property == layer_name {
					log.infof("Enabling Instance Layer: \"%s\"", layer_name)
					continue instance_layer_property_match_found
				}
			}
			log.errorf("Instance Layer \"%s\" is not supported!", required_layer_property)
			return instance, false
		}

		validation_features = vk.ValidationFeaturesEXT {
			sType = .VALIDATION_FEATURES_EXT,
			enabledValidationFeatureCount = len(validation_features_enable_array),
			pEnabledValidationFeatures = raw_data(&validation_features_enable_array),
		}

		instance_create_info.pNext = &validation_features
		instance_create_info.enabledLayerCount = len(instance_layer_property_array)
		instance_create_info.ppEnabledLayerNames = raw_data(&instance_layer_property_array)
	}

	instance_create_result = vk.CreateInstance(&instance_create_info, nil, &instance)
	#partial switch instance_create_result {
	case .SUCCESS:
	case .ERROR_LAYER_NOT_PRESENT:
		log.error("Instance Layer Not Present!")
		return instance, false
	case .ERROR_EXTENSION_NOT_PRESENT:
		log.error("Instance Extension Not Present!")
		return instance, false
	}

	vk.load_proc_addresses_instance(instance)

	return instance, true
}

@(require_results)
surface_create_glfw :: proc(
	instance: vk.Instance,
	window_handle: glfw.WindowHandle,
) -> (
	surface: vk.SurfaceKHR,
	ok: bool,
) #optional_ok {
	check_result(glfw.CreateWindowSurface(instance, window_handle, nil, &surface), "Failed to create GLFW surface!") or_return
	return surface, true
}

@(require_results)
surface_create_wayland :: proc(
	instance: vk.Instance,
	display: ^vk.wl_display,
	wayland_surface: ^vk.wl_surface,
) -> (
	surface: vk.SurfaceKHR,
	ok: bool,
) #optional_ok {
	surface_create_info := vk.WaylandSurfaceCreateInfoKHR {
		sType = .WAYLAND_SURFACE_CREATE_INFO_KHR,
		display = display,
		surface = wayland_surface,
	}
	check_result(vk.CreateWaylandSurfaceKHR(instance, &surface_create_info, nil, &surface), "Failed to create Wayland surface!") or_return
	return surface, true
}

@(require_results)
surface_create_xcb :: proc(
	instance: vk.Instance,
	connection: ^vk.xcb_connection_t,
	window: vk.xcb_window_t,
) -> (
	surface: vk.SurfaceKHR,
	ok: bool,
) #optional_ok {
	surface_create_info := vk.XcbSurfaceCreateInfoKHR {
		sType = .XCB_SURFACE_CREATE_INFO_KHR,
		connection = connection,
		window = window,
	}
	check_result(vk.CreateXcbSurfaceKHR(instance, &surface_create_info, nil, &surface), "Failed to create XCB surface!") or_return
	return surface, true
}

@(require_results)
surface_create_xlib :: proc(
	instance: vk.Instance,
	display: ^vk.XlibDisplay,
	window: vk.XlibWindow,
) -> (
	surface: vk.SurfaceKHR,
	ok: bool,
) #optional_ok {
	surface_create_info := vk.XlibSurfaceCreateInfoKHR {
		sType = .XLIB_SURFACE_CREATE_INFO_KHR,
		dpy = display,
		window = window,
	}
	check_result(vk.CreateXlibSurfaceKHR(instance, &surface_create_info, nil, &surface), "Failed to create Xlib surface!") or_return
	return surface, true
}

@(require_results)
surface_create_win32 :: proc(
	instance: vk.Instance,
	hinstance: vk.HINSTANCE,
	hwnd: vk.HWND,
) -> (
	surface: vk.SurfaceKHR,
	ok: bool,
) #optional_ok {
	surface_create_info := vk.Win32SurfaceCreateInfoKHR {
		sType = .WIN32_SURFACE_CREATE_INFO_KHR,
		hinstance = hinstance,
		hwnd = hwnd,
	}
	check_result(vk.CreateWin32SurfaceKHR(instance, &surface_create_info, nil, &surface), "Failed to create Win32 surface!") or_return
	return surface, true
}

Queue_Type :: enum {
	Graphics,
	Compute,
	Transfer,
	Sparse_Binding,
	Presentation,
}

Queue :: struct {
	handle: vk.Queue,
	family: u32,
}

Queue_Array :: [Queue_Type]Queue

@(require_results)
device_create :: proc(
	physical_device: vk.PhysicalDevice,
	surface: vk.SurfaceKHR,
	device_extension_array: []cstring = { vk.KHR_SWAPCHAIN_EXTENSION_NAME },
	physical_device_features_node: rawptr = nil,
	enable_debug_features: bool = ENABLE_DEBUG_FEATURES,
	temp_allocator := context.temp_allocator,
) -> (
	device: vk.Device,
	queue_array: Queue_Array,
	ok: bool,
) {
	REQUIRED_QUEUE_FAMILY_PROPERTY_FLAGS : vk.QueueFlags : { .GRAPHICS, .COMPUTE, .TRANSFER, .SPARSE_BINDING}
	QUEUE_FAMILY_INVALID : u32 : max(u32)

	device_extension_array := device_extension_array

	api_version: u32

	device_extension_properties_array: []vk.ExtensionProperties
	physical_device_properties: vk.PhysicalDeviceProperties

	found_flags: vk.QueueFlags
	queue_family_properties_array: []vk.QueueFamilyProperties
	queue_priority_array: [len(Queue_Type)]f32
	queue_create_info_count: u32
	queue_create_info_array: [len(Queue_Type)]vk.DeviceQueueCreateInfo

	device_create_info: vk.DeviceCreateInfo

	context.temp_allocator = temp_allocator

	assert(physical_device != nil)
	assert(surface != 0)

	{
		device_extension_properties_count: u32
		vk.EnumerateDeviceExtensionProperties(physical_device, nil, &device_extension_properties_count, nil)
		device_extension_properties_array = make([]vk.ExtensionProperties, device_extension_properties_count, context.temp_allocator)
		vk.EnumerateDeviceExtensionProperties(physical_device, nil, &device_extension_properties_count, raw_data(device_extension_properties_array))
	}

	device_extension_match_found: for required_device_extension in device_extension_array {
		for &device_extension_properties in device_extension_properties_array {
			extension_name: cstring
			extension_name = cstring(raw_data(&device_extension_properties.extensionName))
			if required_device_extension == extension_name {
				log.infof("Enabling Device Extension: \"%s\"", extension_name)
				continue device_extension_match_found
			}
		}
		log.errorf("Device Extension \"%s\" is not supported!", required_device_extension)
		return device, queue_array, false
	}

	vk.GetPhysicalDeviceProperties(physical_device, &physical_device_properties)
	api_version = physical_device_properties.apiVersion
	log.infof("Chosen Device: \"%s\"", strings.truncate_to_byte(string(physical_device_properties.deviceName[:]), 0))
	{
		major, minor, patch := version_extract_major_minor_patch(api_version)
		log.infof("Vulkan Device API Version: %v.%v.%v", major, minor, patch)
	}

	{
		queue_family_properties_count: u32
		vk.GetPhysicalDeviceQueueFamilyProperties(physical_device, &queue_family_properties_count, nil)
		queue_family_properties_array = make([]vk.QueueFamilyProperties, queue_family_properties_count, context.temp_allocator)
		vk.GetPhysicalDeviceQueueFamilyProperties(physical_device, &queue_family_properties_count, raw_data(queue_family_properties_array))
	}

	// PhysicalDevice must support { .GRAPHICS, .COMPUTE, .TRANSFER, .SPARSE_BINDING } and Surface
	for queue_family_properties in queue_family_properties_array {
		found_flags |= queue_family_properties.queueFlags
	}
	if REQUIRED_QUEUE_FAMILY_PROPERTY_FLAGS > found_flags {
		log.errorf("Required Queue Family Property Flags: %v - Found Flags: %v", REQUIRED_QUEUE_FAMILY_PROPERTY_FLAGS, found_flags)
		return device, queue_array, false
	}

	queue_priority_array = f32(1)
	for &queue in queue_array {
		queue.family = QUEUE_FAMILY_INVALID
	}
	{
		find_suitable_queue_family :: proc(
			queue: ^Queue,
			queue_family_properties_array: []vk.QueueFamilyProperties,
			target_queue_flag: vk.QueueFlag,
		) -> (
			ok: bool,
		) {
			for queue_family_properties, idx in queue_family_properties_array {
				if target_queue_flag in queue_family_properties.queueFlags {
					queue.family = cast(u32)idx
					return true
				}
			}

			log.errorf("Failed to find Queue type: %v", target_queue_flag)
			return false
		}

		find_suitable_queue_family(&queue_array[.Graphics], queue_family_properties_array, .GRAPHICS) or_return
		find_suitable_queue_family(&queue_array[.Compute], queue_family_properties_array, .COMPUTE) or_return
		find_suitable_queue_family(&queue_array[.Transfer], queue_family_properties_array, .TRANSFER) or_return
		find_suitable_queue_family(&queue_array[.Sparse_Binding], queue_family_properties_array, .SPARSE_BINDING) or_return

		find_suitable_presentation_queue_family: { // Presentation queue is special case
			for _, idx in queue_family_properties_array {
				surface_is_supported: b32
				if vk.GetPhysicalDeviceSurfaceSupportKHR(physical_device, cast(u32)idx, surface, &surface_is_supported) == .SUCCESS && surface_is_supported {
					queue_array[.Presentation].family = cast(u32)idx
					break find_suitable_presentation_queue_family
				}
			}
			if queue_array[.Presentation].family == QUEUE_FAMILY_INVALID { return device, queue_array, false }
		}
	}

	for queue in queue_array {
		for &queue_create_info in queue_create_info_array {
			if queue_create_info.sType != .DEVICE_QUEUE_CREATE_INFO {
				queue_create_info = vk.DeviceQueueCreateInfo {
					sType = .DEVICE_QUEUE_CREATE_INFO,
					queueFamilyIndex = queue.family,
					queueCount = 1,
					pQueuePriorities = cast([^]f32)&queue_priority_array,
				}
				queue_create_info_count += 1
				break
			}
			else if queue_create_info.queueFamilyIndex == queue.family {
				break
			}
		}
	}

	device_create_info = vk.DeviceCreateInfo {
		sType = .DEVICE_CREATE_INFO,
		pNext = physical_device_features_node,
		queueCreateInfoCount = queue_create_info_count,
		pQueueCreateInfos = raw_data(&queue_create_info_array),
		enabledExtensionCount = cast(u32)len(device_extension_array),
		ppEnabledExtensionNames = raw_data(device_extension_array),
	}

	if enable_debug_features {
		// Device layers are deprecated
		@(static, rodata)
		required_device_layer_property_array := [?]cstring {
			"VK_LAYER_KHRONOS_validation",
		}

		device_layer_properties_array: []vk.LayerProperties

		{
			device_layer_properties_count: u32
			vk.EnumerateDeviceLayerProperties(physical_device, &device_layer_properties_count, nil)
			device_layer_properties_array = make([]vk.LayerProperties, device_layer_properties_count, context.temp_allocator)
			vk.EnumerateDeviceLayerProperties(physical_device, &device_layer_properties_count, raw_data(device_layer_properties_array))
		}

		device_layer_match_found: for required_device_layer_property in required_device_layer_property_array {
			for &device_layer_properties in device_layer_properties_array {
				layer_name: cstring
				layer_name = cstring(raw_data(&device_layer_properties.layerName))
				if required_device_layer_property == layer_name {
					log.infof("Enabling Device Layer: \"%s\"", layer_name)
					continue device_layer_match_found
				}
			}
			log.errorf("Device Validation Layer \"%s\" is not supported!", required_device_layer_property)
			return device, queue_array, false
		}

		device_create_info.enabledLayerCount = len(required_device_layer_property_array)
		device_create_info.ppEnabledLayerNames = raw_data(&required_device_layer_property_array)
	}

	check_result(vk.CreateDevice(physical_device, &device_create_info, nil, &device), "Failed to create Logical Device!") or_return

	vk.load_proc_addresses_device(device) // Avoid dispatch logic

	for &queue in queue_array {
		vk.GetDeviceQueue(device, queue.family, 0, &queue.handle)
	}

	return device, queue_array, true
}

Swapchain :: struct {
	handle: vk.SwapchainKHR,
	image_array: []vk.Image,
	view_array: []vk.ImageView,
	semaphore_render_complete_array: []vk.Semaphore,
	semaphore_presentation_complete_array: []vk.Semaphore,
	surface_format: vk.SurfaceFormatKHR,
	allocator: mem.Allocator,
}

swapchain_destroy :: proc(swapchain: Swapchain, device: vk.Device) {
	context.allocator = swapchain.allocator

	vk.DeviceWaitIdle(device)

	if swapchain.view_array != nil {
		for view in swapchain.view_array {
			if view != 0 {
				vk.DestroyImageView(device, view, nil)
			}
		}
	}
	if swapchain.image_array != nil {
		delete(swapchain.image_array)
		delete(swapchain.view_array)
	}
	if swapchain.handle != 0 {
		vk.DestroySwapchainKHR(device, swapchain.handle, nil)
	}
	for &semaphore in swapchain.semaphore_render_complete_array {
		vk.DestroySemaphore(device, semaphore, nil)
	}
	for &semaphore in swapchain.semaphore_presentation_complete_array {
		vk.DestroySemaphore(device, semaphore, nil)
	}
}

@(require_results)
swapchain_create :: proc(
	window_size: vk.Extent2D,
	#any_int min_image_array: u32,
	physical_device: vk.PhysicalDevice,
	device: vk.Device,
	surface: vk.SurfaceKHR,
	queues: Queue_Array,
	old_swapchain := Swapchain {},
	allocator := context.allocator,
	temp_allocator := context.temp_allocator,
) -> (
	swapchain: Swapchain,
	ok: bool,
) #optional_ok {
	image_count: u32

	context.allocator = allocator
	context.temp_allocator = temp_allocator

	assert(window_size.width > 0)
	assert(window_size.height > 0)
	assert(min_image_array > 0)

	{
		image_usage := vk.ImageUsageFlags {
			.TRANSFER_SRC, .TRANSFER_DST, .COLOR_ATTACHMENT,
		}
		required_format_array := [?]vk.Format {
			.B8G8R8A8_SRGB,
			.B8G8R8A8_UNORM,
			.B8G8R8A8_SNORM,
			.R8G8B8A8_SRGB,
			.R8G8B8A8_SNORM,
			.R8G8B8A8_UNORM,
		}
		required_present_mode_array := [?]vk.PresentModeKHR {
			.MAILBOX,
			.FIFO_RELAXED,
			.FIFO,
			.IMMEDIATE,
		}

		swapchain_create_info: vk.SwapchainCreateInfoKHR

		surface_capabilities: vk.SurfaceCapabilitiesKHR
		presentation_queue_family: u32

		present_mode_chosen: Maybe(vk.PresentModeKHR)
		present_mode_count: u32
		present_mode_array: []vk.PresentModeKHR

		surface_format_count: u32
		surface_format_array: []vk.SurfaceFormatKHR

		vk.GetPhysicalDeviceSurfacePresentModesKHR(physical_device, surface, &present_mode_count, nil)
		present_mode_array = make([]vk.PresentModeKHR, present_mode_count, context.temp_allocator)
		vk.GetPhysicalDeviceSurfacePresentModesKHR(physical_device, surface, &present_mode_count, raw_data(present_mode_array))

		present_mode_match_found: for required_present_mode in required_present_mode_array {
			for present_mode in present_mode_array {
				if present_mode == required_present_mode {
					present_mode_chosen = present_mode
					break present_mode_match_found
				}
			}
		}
		if _, present_mode_chosen_ok := present_mode_chosen.?; !present_mode_chosen_ok {
			log.error("Unable to find suitable Present mode!")
			return swapchain, false
		}
		log.infof("Selected Present Mode: %v", present_mode_chosen.?)

		vk.GetPhysicalDeviceSurfaceFormatsKHR(physical_device, surface, &surface_format_count, nil)
		surface_format_array = make([]vk.SurfaceFormatKHR, surface_format_count, context.temp_allocator)
		vk.GetPhysicalDeviceSurfaceFormatsKHR(physical_device, surface, &surface_format_count, raw_data(surface_format_array))

		format_match_found: for required_format in required_format_array {
			for surface_format in surface_format_array {
				if surface_format.format == required_format {
					swapchain.surface_format = surface_format
					break format_match_found
				}
			}
		}
		if swapchain.surface_format.format == .UNDEFINED {
			log.error("Unable to find suitable Surface format!")
			return swapchain, false
		}
		log.infof("Selected Surface Format: %v", swapchain.surface_format.format)
		log.infof("Selected Surface Color Space: %v", swapchain.surface_format.colorSpace)

		check_result(vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(physical_device, surface, &surface_capabilities), "Unable to get Physical Device Surface capabilities!") or_return

		image_count = max(min_image_array, surface_capabilities.minImageCount)
		image_count = min(image_count, surface_capabilities.maxImageCount if surface_capabilities.maxImageCount != 0 else max(u32))

		presentation_queue_family = queues[.Presentation].family

		swapchain_create_info = vk.SwapchainCreateInfoKHR {
			sType = .SWAPCHAIN_CREATE_INFO_KHR,
			surface = surface,
			minImageCount = image_count,
			imageFormat = swapchain.surface_format.format,
			imageColorSpace = swapchain.surface_format.colorSpace,
			imageExtent = window_size,
			imageArrayLayers = 1,
			imageUsage = image_usage,
			imageSharingMode = .EXCLUSIVE,
			queueFamilyIndexCount = 1,
			pQueueFamilyIndices = &presentation_queue_family,
			preTransform = { .IDENTITY },
			compositeAlpha = { .OPAQUE },
			presentMode = present_mode_chosen.?,
			clipped = true,
			oldSwapchain = old_swapchain.handle,
		}
		check_result(vk.CreateSwapchainKHR(device, &swapchain_create_info, nil, &swapchain.handle), "Failed to create Swapchain!") or_return
		swapchain.allocator = context.allocator
	}

	if old_swapchain.handle != 0 {
		swapchain_destroy(old_swapchain, device)
	}

	vk.GetSwapchainImagesKHR(device, swapchain.handle, &image_count, nil)
	log.infof("Swapchain Image Count: %v", image_count)

	swapchain.image_array = make([]vk.Image, image_count)
	swapchain.view_array = make([]vk.ImageView, image_count)

	#partial switch vk.GetSwapchainImagesKHR(device, swapchain.handle, &image_count, raw_data(swapchain.image_array)) {
	case .SUCCESS:
	case .INCOMPLETE:
		log.warnf("Incomplete Retrieval of Swapchain Images!", image_count)
	case .ERROR_OUT_OF_HOST_MEMORY:
		log.error("Unable to get swapchain image_array!")
		log.error("OUT OF HOST MEMORY!")
		return {}, false
	case .ERROR_OUT_OF_DEVICE_MEMORY:
		log.error("Unable to get swapchain image_array!")
		log.error("OUT OF DEVICE MEMORY!")
		return {}, false
	}

	#no_bounds_check for i: u32 = 0; i < image_count; i += 1 {
		color_attachment_view_create_info: vk.ImageViewCreateInfo
		color_attachment_view_create_success: bool

		color_attachment_view_create_info = vk.ImageViewCreateInfo {
			sType = .IMAGE_VIEW_CREATE_INFO,
			format = swapchain.surface_format.format,
			components = { .R, .G, .B, .A },
			subresourceRange = {
				aspectMask = { .COLOR },
				baseMipLevel = 0,
				levelCount = 1,
				baseArrayLayer = 0,
				layerCount = 1,
			},
			viewType = .D2,
			image = swapchain.image_array[i],
		}

		color_attachment_view_create_success = check_result(vk.CreateImageView(device, &color_attachment_view_create_info, nil, &swapchain.view_array[i]), "Unable to create Image Views for Swapchain!")
		if color_attachment_view_create_success == false {
			swapchain_destroy(swapchain, device)
			return swapchain, false
		}
	}

	{
		semaphore_create_info := vk.SemaphoreCreateInfo {
			sType = .SEMAPHORE_CREATE_INFO,
		}

		swapchain.semaphore_render_complete_array = make([]vk.Semaphore, image_count, allocator)
		for &semaphore in swapchain.semaphore_render_complete_array {
			vk.CreateSemaphore(device, &semaphore_create_info, nil, &semaphore)
		}

		swapchain.semaphore_presentation_complete_array = make([]vk.Semaphore, image_count, allocator)
		for &semaphore in swapchain.semaphore_presentation_complete_array {
			vk.CreateSemaphore(device, &semaphore_create_info, nil, &semaphore)
		}
	}

	log.info("Swapchain created successfully!")
	return swapchain, true
}

@(require_results)
find_optimal_physical_device :: proc(
	instance: vk.Instance,
	temp_allocator := context.temp_allocator,
) -> (
	physical_device: vk.PhysicalDevice,
	ok: bool,
) #optional_ok {
	physical_device_array: []vk.PhysicalDevice

	chosen_physical_device_index: int
	chosen_physical_device_rating: int
	chosen_physical_device_properties: vk.PhysicalDeviceProperties

	context.temp_allocator = temp_allocator

	{
		physical_device_count: u32
		vk.EnumeratePhysicalDevices(instance, &physical_device_count, nil)
		physical_device_array = make([]vk.PhysicalDevice, physical_device_count, context.temp_allocator)
		vk.EnumeratePhysicalDevices(instance, &physical_device_count, raw_data(physical_device_array))

		if physical_device_count == 0 {
			log.error("Unable to enumerate physical devices!")
			return physical_device, false
		}
	}

	chosen_physical_device_index = -1
	chosen_physical_device_rating = -1
	for _, idx in physical_device_array {
		REQUIRED_FLAGS :: vk.QueueFlags { .GRAPHICS, .COMPUTE, .TRANSFER, .SPARSE_BINDING }

		current_physical_device_rating: int

		queue_family_properties_array: []vk.QueueFamilyProperties
		physical_device_properties: vk.PhysicalDeviceProperties

		// Queue Family Properties
		found_flags: vk.QueueFlags

		{
			queue_family_properties_count: u32
			vk.GetPhysicalDeviceQueueFamilyProperties(physical_device_array[idx], &queue_family_properties_count, nil)
			queue_family_properties_array = make([]vk.QueueFamilyProperties, queue_family_properties_count, context.temp_allocator)
			vk.GetPhysicalDeviceQueueFamilyProperties(physical_device_array[idx], &queue_family_properties_count, raw_data(queue_family_properties_array))
		}

		for properties in queue_family_properties_array {
			found_flags |= properties.queueFlags
		}
		if found_flags < REQUIRED_FLAGS { // check: is found_flags only subset of required_flags
			continue
		}

		vk.GetPhysicalDeviceProperties(physical_device_array[idx], &physical_device_properties)
		if physical_device_properties.deviceType == .DISCRETE_GPU {
			current_physical_device_rating |= 0x8000_0000
		}

		/*
			 More can be done to measure the features and/or properties later.
			 Maybe with reflection?
		*/

		// Check competition
		if current_physical_device_rating > chosen_physical_device_rating {
			chosen_physical_device_rating = current_physical_device_rating
			chosen_physical_device_index = idx
			chosen_physical_device_properties = physical_device_properties
		}
	}

	if chosen_physical_device_index < 0 {
		log.error("No suitable physical device found!")
		return physical_device, false
	}

	physical_device = physical_device_array[chosen_physical_device_index]
	return physical_device, true
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

format_has_stencil_component :: #force_inline proc "contextless" (format: vk.Format) -> bool {
	#partial switch format {
	case .D32_SFLOAT_S8_UINT,
			 .D24_UNORM_S8_UINT,
			 .D16_UNORM_S8_UINT:
		return true
	case:
		return false
	}
}
