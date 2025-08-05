package ns_vkjumpstart_vkjs

@(require) import "core:fmt"
@(require) import "core:log"

import vk "vendor:vulkan"

/*
	 `check_result,` `assert_result` and `ensure_result` only exist for a broad, general case
	 DO NOT USE IF you need finer tuned checks on results
*/
@(require_results)
check_result :: proc (
	result: vk.Result,
	error_message: string = "",
	temp_allocator := context.temp_allocator,
	loc := #caller_location,
) -> (
	ok: bool,
) {
	error_msg: string
	if len(error_message) > 0 {
		error_msg = fmt.aprintf("CHECK_RESULT: %v - Message: \"%s\"", result, error_message, allocator = temp_allocator)
	}
	else {
		error_msg = fmt.aprintf("CHECK_RESULT: %v", result, allocator = temp_allocator)
	}

	#partial switch(result) {
	case .SUCCESS, .INCOMPLETE:
		return true
	case:
		log.error(error_msg, location = loc)
		return false
	}

	return true
}

@(disabled = ODIN_DISABLE_ASSERT)
assert_result :: proc (
	result: vk.Result,
	error_message: string = "",
	temp_allocator := context.temp_allocator,
	loc := #caller_location,
) {
	error_msg: string
	if len(error_message) > 0 {
		error_msg = fmt.aprintf("ASSERT_RESULT: %v - Message: \"%s\"", result, error_message, allocator = temp_allocator)
	}
	else {
		error_msg = fmt.aprintf("ASSERT_RESULT: %v", result, allocator = temp_allocator)
	}

	#partial switch(result) {
	case .SUCCESS, .INCOMPLETE:
		return
	case:
		log.panic(error_msg, location = loc)
	}
}

ensure_result :: proc (
	result: vk.Result,
	error_message: string = "",
	temp_allocator := context.temp_allocator,
	loc := #caller_location,
) {
	error_msg: string
	if len(error_message) > 0 {
		error_msg = fmt.aprintf("ENSURE_RESULT: %v - Message: \"%s\"", result, error_message, allocator = temp_allocator)
	}
	else {
		error_msg = fmt.aprintf("ENSURE_RESULT: %v", result, allocator = temp_allocator)
	}

	#partial switch(result) {
	case .SUCCESS, .INCOMPLETE:
		return
	case:
		log.panic(error_msg, location = loc)
	}
}
