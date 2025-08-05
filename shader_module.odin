package ns_vkjumpstart_vkjs

@(require) import "core:fmt"
@(require) import "core:log"
import "core:mem"
import os "core:os/os2"

import vk "vendor:vulkan"

shader_module_create_from_file :: proc(device: vk.Device, file_path: string) -> (vk.ShaderModule, bool) #optional_ok {
	shader_file: ^os.File
	shader_file_open_error: os.Error
	shader_file_size: i64
	shader_code_buf: []byte
	shader_code_buf_alloc_error: mem.Allocator_Error

	shader_module_create_info: vk.ShaderModuleCreateInfo
	shader_module: vk.ShaderModule

	shader_file, shader_file_open_error = os.open(file_path)
	if shader_file_open_error != nil {
		log.errorf("Failed to open shader file \"%s\": %v", file_path, shader_file_open_error)
		return 0, false
	}
	defer os.close(shader_file)

	shader_file_size, _ = os.file_size(shader_file)

	shader_code_buf, shader_code_buf_alloc_error = mem.alloc_bytes(int(shader_file_size), alignment = 4)
	if shader_code_buf_alloc_error != nil {
		log.errorf("Failed to allocate memory for shader module: %v", shader_code_buf_alloc_error)
		return 0, false
	}
	defer free(raw_data(shader_code_buf))

	if bytes_read, shader_file_read_error := os.read(shader_file, shader_code_buf); shader_file_read_error != nil {
		log.errorf("Failed to read shader file \"%s\": %v", file_path, shader_file_read_error)
		return 0, false
	}

	shader_module_create_info = vk.ShaderModuleCreateInfo {
		sType = .SHADER_MODULE_CREATE_INFO,
		codeSize = len(shader_code_buf),
		pCode = cast(^u32)raw_data(shader_code_buf),
	}
	if shader_module_create_err := vk.CreateShaderModule(device, &shader_module_create_info, nil, &shader_module); shader_module_create_err != .SUCCESS {
		log.errorf("Failed to create shader module: %v", shader_module_create_err)
		return 0, false
	}

	return shader_module, true
}
