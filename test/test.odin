package ns_vkjumpstart_test

@(require) import "core:fmt"
@(require) import "core:log"
@(require) import "core:testing"
import "core:mem"
import "core:dynlib"

import vk "vendor:vulkan"
import "vendor:glfw"

import vkjs ".."

@(test)
test :: proc(t: ^testing.T) {
	vulkan_lib: dynlib.Library
	vkGetInstanceProcAddr_func: rawptr
	load_vulkan_ok: bool

	instance: vk.Instance
	instance_create_ok: bool
	instance_extension_array: []cstring

	physical_device: vk.PhysicalDevice
	find_optimal_physical_device_ok: bool

	device: vk.Device
	queue_array: vkjs.Queue_Array
	device_create_ok: bool

	surface: vk.SurfaceKHR
	surface_create_ok: bool

	swapchain: vkjs.Swapchain
	swapchain_create_ok: bool

	dynamic_arena: mem.Dynamic_Arena
	dynamic_arena_allocator: mem.Allocator
	mem.dynamic_arena_init(&dynamic_arena)
	dynamic_arena_allocator = mem.dynamic_arena_allocator(&dynamic_arena)

	window: glfw.WindowHandle
	width := 800
	height := 800

	if glfw.Init() == false {
		log.error("Failed to initialize GLFW")
		testing.fail(t)
	}

	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
	window = glfw.CreateWindow(cast(i32)width, cast(i32)height, "Test Window", nil, nil)
	if window == nil {
		log.error("Failed to create window!")
		testing.fail(t)
	}
	instance_extension_array = glfw.GetRequiredInstanceExtensions()

	vulkan_lib, vkGetInstanceProcAddr_func, load_vulkan_ok = vkjs.load_vulkan()
	if load_vulkan_ok == false {
		log.error("Failed to load vulkan library!")
		testing.fail(t)
	}

	if instance, instance_create_ok = vkjs.instance_create(vkGetInstanceProcAddr_func, instance_extension_array); instance_create_ok == false {
		log.error("Failed to create instance!")
		testing.fail(t)
	}

	if surface, surface_create_ok = vkjs.surface_create_glfw(instance, window); !surface_create_ok {
		log.error("Failed to create surface!")
		testing.fail(t)
	}

	if physical_device, find_optimal_physical_device_ok = vkjs.find_optimal_physical_device(instance); find_optimal_physical_device_ok == false {
		log.error("Failed to find optimal physical device!")
		testing.fail(t)
	}

	{
		device_extension_array := [?]cstring {
			"VK_KHR_swapchain",
			"VK_KHR_buffer_device_address",
			"VK_EXT_descriptor_buffer",
			"VK_KHR_synchronization2",
			"VK_EXT_descriptor_indexing",
			"VK_KHR_dynamic_rendering",
		}

		buffer_device_address_features: vk.PhysicalDeviceBufferDeviceAddressFeatures
		descriptor_buffer_features: vk.PhysicalDeviceDescriptorBufferFeaturesEXT
		synchronization2_features: vk.PhysicalDeviceSynchronization2Features
		descriptor_indexing_features: vk.PhysicalDeviceDescriptorIndexingFeatures
		dynamic_rendering_features: vk.PhysicalDeviceDynamicRenderingFeaturesKHR
		physical_device_features2: vk.PhysicalDeviceFeatures2

		buffer_device_address_features = {
			sType = .PHYSICAL_DEVICE_BUFFER_DEVICE_ADDRESS_FEATURES_KHR,
			pNext = nil,
		}
		descriptor_buffer_features = {
			sType = .PHYSICAL_DEVICE_DESCRIPTOR_BUFFER_FEATURES_EXT,
			pNext = &buffer_device_address_features,
		}
		synchronization2_features = {
			sType = .PHYSICAL_DEVICE_SYNCHRONIZATION_2_FEATURES_KHR,
			pNext = &descriptor_buffer_features,
		}
		descriptor_indexing_features = {
			sType = .PHYSICAL_DEVICE_DESCRIPTOR_INDEXING_FEATURES_EXT,
			pNext = &synchronization2_features,
		}
		dynamic_rendering_features = {
			sType = .PHYSICAL_DEVICE_DYNAMIC_RENDERING_FEATURES_KHR,
			pNext = &descriptor_indexing_features,
		}
		physical_device_features2 = {
			sType = .PHYSICAL_DEVICE_FEATURES_2,
			pNext = &dynamic_rendering_features,
		}
		vk.GetPhysicalDeviceFeatures2(physical_device, &physical_device_features2)

		if buffer_device_address_features.bufferDeviceAddress == false {
			log.error("Buffer device address feature not supported!")
			testing.fail(t)
		}
		if descriptor_buffer_features.descriptorBuffer == false {
			log.error("Descriptor buffer feature not supported!")
			testing.fail(t)
		}
		if synchronization2_features.synchronization2 == false {
			log.error("Synchronization2 features not supported!")
			testing.fail(t)
		}
		if descriptor_indexing_features.descriptorBindingPartiallyBound == false {
			log.error("Partially Bound Descriptor Bindings not supported!")
			testing.fail(t)
		}
		if descriptor_indexing_features.runtimeDescriptorArray == false {
			log.error("Runtime Descriptor Arrays not supported!")
			testing.fail(t)
		}
		if dynamic_rendering_features.dynamicRendering == false {
			log.error("Dynamic Rendering not supported!")
			testing.fail(t)
		}

		buffer_device_address_features = {
			sType = .PHYSICAL_DEVICE_BUFFER_DEVICE_ADDRESS_FEATURES_KHR,
			pNext = nil,
			bufferDeviceAddress = true,
		}
		descriptor_buffer_features = {
			sType = .PHYSICAL_DEVICE_DESCRIPTOR_BUFFER_FEATURES_EXT,
			pNext = &buffer_device_address_features,
			descriptorBuffer = true,
		}
		descriptor_indexing_features = {
			sType = .PHYSICAL_DEVICE_DESCRIPTOR_INDEXING_FEATURES_EXT,
			pNext = &synchronization2_features,
			descriptorBindingPartiallyBound = true,
			runtimeDescriptorArray = true,
		}

		if device, queue_array, device_create_ok = vkjs.device_create(physical_device, surface, device_extension_array[:], &physical_device_features2); device_create_ok == false {
			log.error("Failed to create logical device!")
			testing.fail(t)
		}
	}

	if swapchain, swapchain_create_ok = vkjs.swapchain_create({ cast(u32)width, cast(u32)height }, 3, physical_device, device, surface, queue_array, allocator = dynamic_arena_allocator); swapchain_create_ok == false {
		log.error("Failed to create swapchain!")
		testing.fail(t)
	}

	// Heap
	heap: vkjs.Heap
	vkjs.heap_init(&heap, physical_device, device)
}
