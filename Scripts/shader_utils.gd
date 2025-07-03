

class_name ShaderUtils

static func LoadWithIncludes(path: String, result_lines: Array[String] = []) -> String:

	# Opening target file, raising an error if it does not exist
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("Could not open shader file : %s" % path)
		return ""
		
	# Starting with result_lines empty, but we will pass it to the recursive
	# calls when we encounter an include line
	
	# Regex used to look for includes
	var regex := RegEx.new()
	regex.compile('#include\\s+"([^"]+)"')

	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		var result := regex.search(line)
		
		if result: # regex matches, this is an include line
			var include_path := result.get_string(1)
			LoadWithIncludes("res://" + include_path, result_lines)
		else: # regular line
			result_lines.push_back(line)
	
	return "\n".join(result_lines)
