#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float3 position [[attribute(0)]];
    float4 color    [[attribute(1)]];
};

struct VertexOut {
    float4 position [[position]];
    float4 color;
    float3 normal;
};

struct Uniforms {
    float4x4 mvp;
};

vertex VertexOut cube_vertex(VertexIn in [[stage_in]],
                            constant Uniforms& uniforms [[buffer(1)]]) {
    VertexOut out;
    out.position = uniforms.mvp * float4(in.position, 1.0);
    out.color = in.color;
    out.normal = float3(0, 0, 1); // not used — colour is pre-computed on CPU
    return out;
}

fragment float4 cube_fragment(VertexOut in [[stage_in]]) {
    return in.color;
}
