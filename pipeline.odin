package ns_vkjumpstart_vkjs

@(require) import "core:fmt"
@(require) import "core:log"

import vk "vendor:vulkan"

@(require_results)
pipeline_vertex_input_state_create_info :: proc (
	vertex_binding_description_array: []vk.VertexInputBindingDescription = nil,
	vertex_input_attribute_description_array: []vk.VertexInputAttributeDescription = nil,
	flags: vk.PipelineVertexInputStateCreateFlags = {},
) -> (
	vk.PipelineVertexInputStateCreateInfo,
) {
	return {
		sType = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
		flags = flags,
		vertexBindingDescriptionCount = cast(u32)len(vertex_binding_description_array),
		pVertexBindingDescriptions = raw_data(vertex_binding_description_array),
		vertexAttributeDescriptionCount = cast(u32)len(vertex_input_attribute_description_array),
		pVertexAttributeDescriptions = raw_data(vertex_input_attribute_description_array),
	}
}

@(require_results)
pipeline_input_assembly_state_create_info :: proc (
	primitive_topology: vk.PrimitiveTopology,
	primitive_restart_enable: b32 = false,
	flags: vk.PipelineInputAssemblyStateCreateFlags = {},
) -> (
	vk.PipelineInputAssemblyStateCreateInfo,
) {
	return {
		sType = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
		flags = flags,
		topology = primitive_topology,
		primitiveRestartEnable = primitive_restart_enable,
	}
}

@(require_results)
pipeline_tessellation_state_create_info :: proc (
	#any_int patch_control_points: u32,
	flags: vk.PipelineTessellationStateCreateFlags = {},
) -> (
	vk.PipelineTessellationStateCreateInfo,
) {
	return {
		sType = .PIPELINE_TESSELLATION_STATE_CREATE_INFO,
		flags = flags,
		patchControlPoints = patch_control_points,
	}
}

@(require_results)
pipeline_viewport_state_create_info :: proc (
	viewport_array: []vk.Viewport,
	scissor_array: []vk.Rect2D,
	flags: vk.PipelineViewportStateCreateFlags = {},
) -> (
	vk.PipelineViewportStateCreateInfo,
) {
	return {
		sType = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
		viewportCount = cast(u32)len(viewport_array),
		pViewports = raw_data(viewport_array),
		scissorCount = cast(u32)len(scissor_array),
		pScissors = raw_data(scissor_array),
	}
}

@(require_results)
pipeline_rasterization_state_create_info :: proc (
	front_face: vk.FrontFace,
	polygon_mode: vk.PolygonMode,
	cull_mode: vk.CullModeFlags,
	rasterizer_discard_enable: b32 = false,
	line_width: f32 = 1,
	depth_clamp_enable: b32 = false,
	depth_bias_enable: b32 = false,
	depth_bias_constant_factor: f32 = 0,
	depth_bias_clamp: f32 = 0,
	depth_bias_slope_factor: f32 = 0,
	flags: vk.PipelineRasterizationStateCreateFlags = {},
) -> (
	vk.PipelineRasterizationStateCreateInfo,
) {
	return {
		sType = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
		flags = flags,
		depthClampEnable = depth_clamp_enable,
		rasterizerDiscardEnable = rasterizer_discard_enable,
		polygonMode = polygon_mode,
		cullMode = cull_mode,
		frontFace = front_face,
		depthBiasEnable = depth_bias_enable,
		depthBiasConstantFactor = depth_bias_constant_factor,
		depthBiasClamp = depth_bias_clamp,
		depthBiasSlopeFactor = depth_bias_slope_factor,
		lineWidth = line_width,
	}
}

@(require_results)
pipeline_multisample_state_create_info :: proc (
	rasterization_samples: vk.SampleCountFlags = { ._1 },
	sample_mask: ^vk.SampleMask = nil,
	sample_shading_enable: b32 = false,
	min_sample_shading: f32 = 0,
	alpha_to_coverage_enable: b32 = false,
	alpha_to_one_enable: b32 = false,
	flags: vk.PipelineMultisampleStateCreateFlags = {},
) -> (
	vk.PipelineMultisampleStateCreateInfo,
) {
	@(static, rodata)
	static_sample_mask: vk.SampleMask = 1

	sample_mask := sample_mask

	sample_mask = sample_mask if sample_mask != nil else &static_sample_mask

	return {
		sType = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
		flags = flags,
		rasterizationSamples = rasterization_samples,
		sampleShadingEnable = sample_shading_enable,
		minSampleShading = min_sample_shading,
		pSampleMask = sample_mask,
		alphaToCoverageEnable = alpha_to_coverage_enable,
		alphaToOneEnable = alpha_to_one_enable,
	}
}

@(require_results)
pipeline_depth_stencil_state_create_info :: proc (
	depth_test_enable: b32 = false,
	depth_write_enable: b32 = false,
	depth_compare_op: vk.CompareOp = {},
	depth_bounds_test_enable: b32 = false,
	min_depth_bounds: f32 = 0,
	max_depth_bounds: f32 = 0,
	stencil_test_enable: b32 = true,
	front: vk.StencilOpState = {},
	back: vk.StencilOpState = {},
	flags: vk.PipelineDepthStencilStateCreateFlags = {},
) -> (
	vk.PipelineDepthStencilStateCreateInfo,
) {
	return {
		sType = .PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
		flags = flags,
		depthTestEnable = depth_test_enable,
		depthWriteEnable = depth_write_enable,
		depthCompareOp = depth_compare_op,
		depthBoundsTestEnable = depth_bounds_test_enable,
		stencilTestEnable = stencil_test_enable,
		front = front,
		back = back,
		minDepthBounds = min_depth_bounds,
		maxDepthBounds = max_depth_bounds,
	}
}

PIPELINE_COLOR_BLEND_ATTACHMENT_STATE_NONE :: vk.PipelineColorBlendAttachmentState {
	blendEnable = false,
}
PIPELINE_COLOR_BLEND_ATTACHMENT_STATE_OPAQUE_ALPHA :: vk.PipelineColorBlendAttachmentState {
	blendEnable = true,
	srcColorBlendFactor = .ONE,
	dstColorBlendFactor = .ZERO,
	colorBlendOp = .ADD,
	srcAlphaBlendFactor = .ONE,
	dstAlphaBlendFactor = .ZERO,
	alphaBlendOp = .ADD,
	colorWriteMask = { .R, .G, .B, .A },
}
PIPELINE_COLOR_BLEND_ATTACHMENT_STATE_TRANSPARENT_ALPHA :: vk.PipelineColorBlendAttachmentState {
	blendEnable = true,
	srcColorBlendFactor = .SRC_ALPHA,
	dstColorBlendFactor = .ONE_MINUS_SRC_ALPHA,
	colorBlendOp = .ADD,
	srcAlphaBlendFactor = .ONE,
	dstAlphaBlendFactor = .ZERO,
	alphaBlendOp = .ADD,
	colorWriteMask = { .R, .G, .B, .A },
}

@(require_results)
pipeline_color_blend_state_create_info :: proc (
	color_blend_attachment_array: []vk.PipelineColorBlendAttachmentState = { PIPELINE_COLOR_BLEND_ATTACHMENT_STATE_OPAQUE_ALPHA },
	blend_constants: [4]f32 = { 1, 1, 1, 1 },
	logic_op_enable: b32 = false,
	logic_op: vk.LogicOp = {},
	flags: vk.PipelineColorBlendStateCreateFlags = {},
) -> (
	vk.PipelineColorBlendStateCreateInfo,
) {
	return {
		sType = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
		flags = flags,
		logicOpEnable = logic_op_enable,
		logicOp = logic_op,
		attachmentCount = cast(u32)len(color_blend_attachment_array),
		pAttachments = raw_data(color_blend_attachment_array),
		blendConstants = blend_constants,
	}
}

@(require_results)
pipeline_dynamic_state_create_info :: proc (
	dynamic_state_array: []vk.DynamicState = nil,
	flags: vk.PipelineDynamicStateCreateFlags = {},
) -> (
	vk.PipelineDynamicStateCreateInfo,
) {
	return {
		sType = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
		flags = flags,
		dynamicStateCount = cast(u32)len(dynamic_state_array),
		pDynamicStates = raw_data(dynamic_state_array),
	}
}
