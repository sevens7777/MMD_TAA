// 默认背景颜色
float4 BackColor
<
	string UIName = "BackColor";
	string UIWidget = "Color";
	bool UIVisible = true;
> = float4(0, 0, 0, 0);

// 不知道是什么
float Script : STANDARDSGLOBAL <
	string ScriptOutput = "color";
	string ScriptClass = "sceneorobject";
	string ScriptOrder = "postprocess";
> = 0.8;

//速度下限值
float VelocityUnderCut
<
    string UIName = "VelocityUnderCut";
    string UIWidget = "Slider";
    bool UIVisible = true;
    float UIMin = 0.0;
    float UIMax = 3.0;
> = float(0.006);

//获取α值
float alpha1 : CONTROLOBJECT < string name = "(self)"; string item = "Tr"; > ;

// TAA.x的缩放值（Si）
float scaling : CONTROLOBJECT < string name = "(self)"; > ;

// 屏幕大小
float2 ViewportSize : VIEWPORTPIXELSIZE;
static float ViewportAspect = ViewportSize.x / ViewportSize.y;
static float2 ViewportOffset = (float2(0.5, 0.5) / ViewportSize);

//获取motion vector（裁剪空间坐标）
texture VelocityRT: OFFSCREENRENDERTARGET <
    string Description = "OffScreen RenderTarget for TAA.fx";
    float2 ViewPortRatio = { 1.0, 1.0 };
    float4 ClearColor = { 0.5, 0.5, 1, 0 };
    float ClearDepth = 1.0;
    string Format = "A32B32G32R32F";
    bool AntiAlias = false;
    int MipLevels = 1;
    string DefaultEffect =
        "self = hide;"
        "* = TAAVelocity.fx;"
    ;
> ;
sampler VelocitySampler = sampler_state {
    texture = <VelocityRT>;
    AddressU = CLAMP;
    AddressV = CLAMP;
    Filter = LINEAR;
};


// 深度缓冲区
texture2D DepthBuffer : RENDERDEPTHSTENCILTARGET <
    float2 ViewPortRatio = { 1.0,1.0 };
    string Format = "D24S8";
> ;

// 用于记录原始绘制结果的渲染目标
texture2D ScnMap : RENDERCOLORTARGET <
    float2 ViewPortRatio = { 1.0,1.0 };
    int MipLevels = 0;
    string Format = "A8R8G8B8";
> ;
sampler2D ScnSamp = sampler_state {
    texture = <ScnMap>;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
    MipFilter = LINEAR;
    AddressU = CLAMP;
    AddressV = CLAMP;
};

// 用于记录上一帧对当前帧的画面影响
texture2D ScnMap2 : RENDERCOLORTARGET <
    float2 ViewPortRatio = { 1.0,1.0 };
    int MipLevels = 0;
    string Format = "A8R8G8B8";
> ;
sampler2D ScnSamp2 = sampler_state {
    texture = <ScnMap2>;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
    MipFilter = LINEAR;
    AddressU = CLAMP;
    AddressV = CLAMP;
};


///////////////////////////////////////////////////////////////////
//若motion vector长度小于下限则拉长
float2 MB_VelocityPreparation(float2 rawvec) {
    float2 vel = (rawvec.x + 1, 1 - rawvec.y) / 2;
    float len = length(vel);
    vel = max(0, len - VelocityUnderCut) * normalize(vel);

    return vel * scaling;
}


//////////////////////////////////////////////////////////////////
// 公共顶点着色器
struct VS_OUTPUT {
    float4 Pos            : POSITION;
    float2 Tex            : TEXCOORD0;
    float Depth           : TEXCOORD1;
};

VS_OUTPUT VS_passDraw(float4 Pos : POSITION, float2 Tex : TEXCOORD0) {
    VS_OUTPUT Out = (VS_OUTPUT)0;

    
    Out.Pos = Pos;
    Out.Tex = Tex + ViewportOffset;
    Out.Depth = tex2Dlod(ScnSamp, float4(Tex, 0, 0)).z;

    return Out;
}

//调整偏移uv量 弱化遮挡造成的错误 并采样速度
float2 MB_GetBlurMapAround(float2 Tex, float Depth)
{
    float3 result = float3(0.0, 0.0, Depth);
    float2 ABXY = 0;
    [unroll]
    for (int k = 0; k < 9; k++) {
        ABXY = (int(k / 3) - 1, int(k % 3) - 1);
        float neighbor = tex2Dlod(ScnSamp, float4((ABXY / ViewportSize + Tex), 0, 0)).z;
        // 获取离相机最近的点，这里使用 lerp 是避免在shader中写分支判断
        result = lerp(result, float3(ABXY, neighbor), step(result.z, neighbor));
    }

    float2 close = tex2Dlod(VelocitySampler, float4(Tex + result.xy, 0, 0)).xy;
    return MB_VelocityPreparation(close);
}


////////////////////////////////////////////////////////////////////////////////////////////////
//根据motion vector进行方向模糊
float4 PS_DirectionalBlur(float2 Tex: TEXCOORD0, float Depth: TEXCOORD1) : COLOR{

    float4 Color = 0;
    float4 vm;
    float2 ABXY = 0;
    float4 AABBMax = tex2Dlod(ScnSamp, float4(Tex, 0, 0));
    float4 AABBMin = tex2Dlod(ScnSamp, float4(Tex, 0, 0));

    [unroll]
    for (int k = 0; k < 9; k++) {
        ABXY = (int(k / 3) - 1, int(k % 3) - 1);
        vm = tex2Dlod(ScnSamp, float4(ABXY / ViewportSize + Tex, 0, 0));
        AABBMin = min(AABBMin, vm);
        AABBMax = max(AABBMax, vm);
    }
    float4 History = tex2Dlod(ScnSamp2, float4(Tex - MB_GetBlurMapAround(Tex, Depth), 0, 0));

    // 下面是clip计算的过程
    float4 Filtered = (AABBMin + AABBMax) * 0.5f;
    float4 RayDir = Filtered - History;
    RayDir = abs(RayDir) < (1 / 65536) ? (1 / 65536) : RayDir;
    float4 InvRayDir = 1 / RayDir;
    
    // 获取和Box相交的位置
    float4 MinIntersect = (AABBMin - History) * InvRayDir;
    float4 MaxIntersect = (AABBMax - History) * InvRayDir;
    float4 EnterIntersect = min(MinIntersect, MaxIntersect);
    float ClipBlend = max(EnterIntersect.x, max(EnterIntersect.y, EnterIntersect.z));
    ClipBlend = saturate(ClipBlend);

    // 取得和 ClipBox 的相交点
    Color = lerp(History, Filtered, ClipBlend);
    return Color;
}



float4 PS_MixLineBluer(float2 Tex: TEXCOORD0) : COLOR{

    float4 Color;

    float4 CurColor = tex2Dlod(ScnSamp, float4(Tex,0,0));
    float4 LastColor = tex2Dlod(ScnSamp2, float4(Tex,0,0));

    Color.rgb = lerp(CurColor.rgb, LastColor.rgb, 0.05f * alpha1);
    Color.a = max(CurColor.a, LastColor.a);

    return Color;
}

// 复制历史帧的像素着色器
float4 PS_CopyHistory(float2 uv : TEXCOORD0) : COLOR {
    return tex2D(ScnSamp, uv); // 从 ScnMap 复制到 ScnMap2
}

const float4 ClearColor = float4(0, 0, 0, 0);
const float ClearDepth = 1.0;

technique TAA <
    string Script =
    "RenderColorTarget0=ScnMap;"
    "RenderDepthStencilTarget=DepthBuffer;"
    "ClearSetColor=BackColor;"
    "ClearSetDepth=ClearDepth;"
    "Clear=Color;"
    "Clear=Depth;"
    "ScriptExternal=Color;"

    "RenderColorTarget0=ScnMap;"
    "RenderDepthStencilTarget=DepthBuffer;"
    "ClearSetColor=BackColor;"
    "ClearSetDepth=ClearDepth;"
    "Pass=HistoryCal;"

    "RenderColorTarget0=;"
    "RenderDepthStencilTarget=;"
    "Clear=Color;"
    "Pass=MixLineBluer;"

    "RenderColorTarget0=ScnMap2;"
    "RenderDepthStencilTarget=DepthBuffer;"
    "ClearSetColor=BackColor;"
    "ClearSetDepth=ClearDepth;"
    "Clear=Color;"
    "Clear=Depth;"
    "Pass=HistoryCal;"
    ;
> {

    pass HistoryCal < string Script = "Draw=Buffer;"; > {
        AlphaBlendEnable = false; AlphaTestEnable = false;
        ZEnable = false; ZWriteEnable = false;
        VertexShader = compile vs_3_0 VS_passDraw();
        PixelShader = compile ps_3_0 PS_DirectionalBlur();
    }

    pass MixLineBluer < string Script = "Draw=Buffer;"; > {
        AlphaBlendEnable = false; AlphaTestEnable = false;
        ZEnable = false; ZWriteEnable = false;
        VertexShader = compile vs_3_0 VS_passDraw();
        PixelShader = compile ps_3_0 PS_MixLineBluer();
    }

    pass CopyHistory < string Script = "Draw=Buffer;"; > {
        AlphaBlendEnable = false; AlphaTestEnable = false;
        ZEnable = false; ZWriteEnable = false;
        VertexShader = compile vs_3_0 VS_passDraw();
        PixelShader = compile ps_3_0 PS_CopyHistory();
    }

}