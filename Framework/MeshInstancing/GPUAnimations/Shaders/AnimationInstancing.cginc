﻿// Upgrade NOTE: upgraded instancing buffer 'Props' to new syntax.

#ifndef ANIMATION_INSTANCING_INCLUDED
#define ANIMATION_INSTANCING_INCLUDED

#if !defined(_VERTEX_SKINNING)

#define APPLY_VERTEX_SKINNING(vertex, boneWeights, boneIDs, normal, tangent)

#else // _VERTEX_SKINNING

#if defined(UNITY_PASS_SHADOWCASTER)
#define _SKIN_POS_ONLY
#endif

uniform int _boneCount;
uniform sampler2D _animationTexture;
uniform int _animationTextureWidth;
uniform int _animationTextureHeight;

#if (SHADER_TARGET < 30 || SHADER_API_GLES)
uniform float _currentAnimationFrame;
uniform float _currentAnimationWeight;
uniform float _previousAnimationFrame;
#else
UNITY_INSTANCING_BUFFER_START(Props)
	UNITY_DEFINE_INSTANCED_PROP(float, _currentAnimationFrame)
#define _currentAnimationFrame_arr Props
	UNITY_DEFINE_INSTANCED_PROP(float, _currentAnimationWeight)
#define _currentAnimationWeight_arr Props
	UNITY_DEFINE_INSTANCED_PROP(float, _previousAnimationFrame)
#define _previousAnimationFrame_arr Props
UNITY_INSTANCING_BUFFER_END(Props)
#endif

half4x4 loadAnimationInstanceMatrixFromTexture(uint frameIndex, uint boneIndex)
{
	uint pixelsPerFrame = 4;
	
	//how many frames per row?
	uint framesPerRow = _animationTextureWidth / pixelsPerFrame;
	float row = frameIndex / framesPerRow;
	
	int2 uv;
	uv.y = (row * _boneCount);
	uv.x = pixelsPerFrame * (frameIndex - _animationTextureWidth / pixelsPerFrame * uv.y);
	uv.y += boneIndex;

	float2 uvFrame;
	uvFrame.x = uv.x / (float)_animationTextureWidth;
	uvFrame.y = uv.y / (float)_animationTextureHeight;
	half4 uvf = half4(uvFrame, 0, 0);

	float offset = 1.0f / (float)_animationTextureWidth;
	half4 c1 = tex2Dlod(_animationTexture, uvf);
	uvf.x = uvf.x + offset;
	half4 c2 = tex2Dlod(_animationTexture, uvf);
	uvf.x = uvf.x + offset;
	half4 c3 = tex2Dlod(_animationTexture, uvf);
	uvf.x = uvf.x + offset;
	//half4 c4 = tex2Dlod(_animationTexture, uvf);
	half4 c4 = half4(0, 0, 0, 1);
	//float4x4 m = float4x4(c1, c2, c3, c4);
	half4x4 m;
	m._11_21_31_41 = c1;
	m._12_22_32_42 = c2;
	m._13_23_33_43 = c3;
	m._14_24_34_44 = c4;
	return m;
}


half4x4 calcVertexMatrix(float4 boneWeights, half4 boneIDs, int frame)
{
	int frameIndex = floor(frame);
	half4x4 localToWorldMatrixPre = loadAnimationInstanceMatrixFromTexture(frameIndex, boneIDs.x) * boneWeights.x;
	if (boneWeights.y > 0.0f)
		localToWorldMatrixPre = localToWorldMatrixPre + loadAnimationInstanceMatrixFromTexture(frameIndex, boneIDs.y) * boneWeights.y;
	if (boneWeights.z > 0.0f)
		localToWorldMatrixPre = localToWorldMatrixPre + loadAnimationInstanceMatrixFromTexture(frameIndex, boneIDs.z) * boneWeights.z;
	if (boneWeights.w > 0.0f)
		localToWorldMatrixPre = localToWorldMatrixPre + loadAnimationInstanceMatrixFromTexture(frameIndex, boneIDs.w) * boneWeights.w;
		
	return localToWorldMatrixPre;
}

void calcVertexFromAnimation(float4 boneWeights, half4 boneIDs, float curFrame, inout half4 vertex, inout half3 normal, inout half4 tangent)
{
	int prevFrame = floor(curFrame);
	int nextFrame = prevFrame + 1;
	float frameLerp = curFrame - prevFrame;
	
	half4x4 localToWorldMatrixPre = calcVertexMatrix(boneWeights, boneIDs, prevFrame);
	half4x4 localToWorldMatrixNext = calcVertexMatrix(boneWeights, boneIDs, nextFrame);

	//Work out vertex pos
	half4 localPosPrev = mul(vertex, localToWorldMatrixPre);
	half4 localPosNext = mul(vertex, localToWorldMatrixNext);
	vertex = lerp(localPosPrev, localPosNext, frameLerp);
	
	//Work out normal
	half3 localNormPrev = mul(normal.xyz, (float3x3)localToWorldMatrixPre);
	half3 localNormNext = mul(normal.xyz, (float3x3)localToWorldMatrixNext);
	normal = normalize(lerp(localNormPrev, localNormNext, frameLerp));
	
	//Work out tangent
	half3 localTanPrev = mul(tangent.xyz, (float3x3)localToWorldMatrixPre);
	half3 localTanNext = mul(tangent.xyz, (float3x3)localToWorldMatrixNext);
	tangent.xyz = normalize(lerp(localTanPrev, localTanNext, frameLerp));
}

void calcVertexFromAnimation(float4 boneWeights, half4 boneIDs, float curFrame, inout half4 vertex)
{
	int prevFrame = floor(curFrame);
	int nextFrame = prevFrame + 1;
	float frameLerp = curFrame - prevFrame;
	
	half4x4 localToWorldMatrixPre = calcVertexMatrix(boneWeights, boneIDs, prevFrame);
	half4x4 localToWorldMatrixNext = calcVertexMatrix(boneWeights, boneIDs, nextFrame);

	//Work out vertex pos
	half4 localPosPrev = mul(vertex, localToWorldMatrixPre);
	half4 localPosNext = mul(vertex, localToWorldMatrixNext);
	vertex = lerp(localPosPrev, localPosNext, frameLerp);
}

void gpuSkinning(float4 boneWeights, half4 boneIDs, inout half4 vertex, inout half3 normal, inout half4 tangent)
{
#if (SHADER_TARGET < 30 || SHADER_API_GLES)
	float curAnimFrame = _currentAnimationFrame;
	float curAnimWeight = _currentAnimationWeight;
	float preAnimFrame = _previousAnimationFrame;
#else
	float curAnimFrame = UNITY_ACCESS_INSTANCED_PROP(_currentAnimationFrame_arr, _currentAnimationFrame);
	float curAnimWeight = UNITY_ACCESS_INSTANCED_PROP(_currentAnimationWeight_arr, _currentAnimationWeight);
	float preAnimFrame = UNITY_ACCESS_INSTANCED_PROP(_previousAnimationFrame_arr, _previousAnimationFrame);
#endif

	//Find vertex position for currently playing animation
	half4 curAnimVertex = vertex;
	half3 curAnimNormal = normal;
	half4 curAnimTangent = tangent;
	
#if _SKIN_POS_ONLY
	calcVertexFromAnimation(boneWeights, boneIDs, curAnimFrame, curAnimVertex);
#else
	calcVertexFromAnimation(boneWeights, boneIDs, curAnimFrame, curAnimVertex, curAnimNormal, curAnimTangent);	
#endif

	//Find vertex position for previous animation if blending on top of it and lerp current one on top
	if (curAnimWeight < 1.0)
	{
		half4 prevAnimVertex = vertex;
#if _SKIN_POS_ONLY
		calcVertexFromAnimation(boneWeights, boneIDs, preAnimFrame, prevAnimVertex);		
#else
		half3 prevAnimNormal = normal;
		half4 prevAnimTangent = tangent;
		calcVertexFromAnimation(boneWeights, boneIDs, preAnimFrame, prevAnimVertex, prevAnimNormal, prevAnimTangent);
		
		curAnimNormal = normalize(lerp(prevAnimNormal, curAnimNormal, curAnimWeight));
		curAnimTangent = normalize(lerp(prevAnimTangent, curAnimTangent, curAnimWeight));
#endif	
		curAnimVertex = lerp(prevAnimVertex, curAnimVertex, curAnimWeight);
	}
	
	vertex = curAnimVertex;
	normal = curAnimNormal;
	tangent = curAnimTangent;
}

#define APPLY_VERTEX_SKINNING(vertex, boneWeights, boneIDs, normal, tangent) \
	gpuSkinning(boneWeights, boneIDs, vertex, normal, tangent);

#endif // _VERTEX_SKINNING

#endif // ANIMATION_INSTANCING_INCLUDED