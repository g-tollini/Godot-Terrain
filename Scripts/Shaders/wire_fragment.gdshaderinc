#version 450

#include "Scripts/Shaders/buffer.gdshaderinc"

layout(location = 2) in vec4 a_Color;

layout(location = 0) out vec4 frag_color;

void main(){
	frag_color = vec4(1, 0, 0, 1);
}
