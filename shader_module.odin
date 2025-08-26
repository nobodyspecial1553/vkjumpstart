package ns_vkjumpstart_vkjs

@(require) import "core:fmt"
@(require) import "core:log"
import "core:mem"
import "core:io"
import "core:bufio"
import "core:slice"
import os "core:os/os2"

import vk "vendor:vulkan"

@(require_results)
shader_module_create_from_stream :: proc(
	device: vk.Device,
	in_stream: io.Stream,
	allocator := context.allocator,
) -> (
	shader_module: vk.ShaderModule,
	ok: bool,
) #optional_ok {
	shader_byte_size: int
	shader_code_buffer: [dynamic]u32
	shader_code_buffer_alloc_error: mem.Allocator_Error

	shader_module_create_info: vk.ShaderModuleCreateInfo

	in_stream_capabilities: io.Stream_Mode_Set

	context.allocator = allocator

	assert(device != nil)

	in_stream_capabilities = io.query(in_stream)

	if .Read not_in in_stream_capabilities {
		log.error("Stream is incapable of reading!")
		return shader_module, false
	}

	defer delete(shader_code_buffer)
	if .Size in in_stream_capabilities {
		in_stream_size: i64
		bytes_read: int
		io_error: io.Error

		in_stream_size, _ = io.size(in_stream)
		shader_code_buffer = make([dynamic]u32, in_stream_size, allocator)

		bytes_read, io_error = io.read_full(in_stream, slice.reinterpret([]u8, shader_code_buffer[:]))
		if io_error != nil {
			log.errorf("Only read %v of %v bytes: %v", bytes_read, in_stream_size, io_error)
			return shader_module, false
		}
		if bytes_read % 4 != 0 {
			log.errorf("Bytes read '%v' was not divisible by four!", bytes_read)
			return shader_module, false
		}
	}
	else {
		shader_code_buffer_temp: [4096]byte

		shader_code_buffer.allocator = allocator

		read_shader_code_from_stream: for {
			bytes_read: int
			io_error: io.Error

			bytes_read, io_error = io.read_at_least(in_stream, shader_code_buffer_temp[:], 4)
			if bytes_read > 0 {
				if bytes_read % 4 != 0 {
					log.errorf("Bytes read '%v' was not divisible by four!", bytes_read)
					return shader_module, false
				}
				append(&shader_code_buffer, ..slice.reinterpret([]u32, shader_code_buffer_temp[:bytes_read]))
			}

			#partial switch io_error {
			case .Empty, .None:
			case .EOF, .Unexpected_EOF:
				break read_shader_code_from_stream
			case:
				log.errorf("Failed to read shader code buffer from stream: %v", io_error)
				return shader_module, false
			}
		}
	}

	shader_module_create_info = vk.ShaderModuleCreateInfo {
		sType = .SHADER_MODULE_CREATE_INFO,
		codeSize = len(shader_code_buffer),
		pCode = cast(^u32)raw_data(shader_code_buffer),
	}
	if shader_module_create_err := vk.CreateShaderModule(device, &shader_module_create_info, nil, &shader_module); shader_module_create_err != .SUCCESS {
		log.errorf("Failed to create shader module: %v", shader_module_create_err)
		return 0, false
	}

	return shader_module, true
}

@(require_results)
shader_module_create_from_file :: proc(
	device: vk.Device,
	file_path: string,
	allocator := context.allocator,
) -> (
	shader_module: vk.ShaderModule,
	ok: bool,
) #optional_ok {
	shader_file: ^os.File
	shader_file_open_error: os.Error

	buffered_reader: bufio.Reader
	buffered_reader_stream: io.Stream

	context.allocator = allocator

	assert(device != nil)
	assert(file_path != "")

	shader_file, shader_file_open_error = os.open(file_path)
	if shader_file_open_error != nil {
		log.errorf("Failed to open shader file \"%s\": %v", file_path, shader_file_open_error)
		return shader_module, false
	}
	defer os.close(shader_file)

	bufio.reader_init(&buffered_reader, shader_file.stream, allocator = allocator)
	defer bufio.reader_destroy(&buffered_reader)
	buffered_reader_stream = bufio.reader_to_stream(&buffered_reader)

	return shader_module_create_from_stream(device, buffered_reader_stream, allocator)
}

shader_module_create :: proc {
	shader_module_create_from_stream,
	shader_module_create_from_file,
}
