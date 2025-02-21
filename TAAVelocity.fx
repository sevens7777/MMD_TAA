// ���ô�͸����������ֵ
float TransparentThreshold = 0.5;

// ʹ������͸������Ϊ͸���ȡ�1��Ч��0��Ч
#define TRANS_TEXTURE  1

////////////////////////////////////////////////////////////////////////////////////////////////
//Clone�BЯ�C��

//ָ��Clone�Ĳ�����ȡ
#define CLONE_PARAMINCLUDE

//ɾ������ע�ͣ�ָ����¡Ч���ļ���
//include "Clone.fx"


//�������������
#ifndef CLONE_MIPMAPTEX_SIZE
int CloneIndex = 0; //ѭ������
int CloneCount = 1; //������
float4 ClonePos(float4 Pos) { return Pos; }
#endif

////////////////////////////////////////////////////////////////////////////////////////////////


// ����任����
float4x4 WorldViewProjMatrix      : WORLDVIEWPROJECTION;
float4x4 WorldMatrix              : WORLD;
float4x4 WorldViewMatrix          : WORLDVIEW;
float4x4 ProjectionMatrix         : PROJECTION;
float4x4 ViewProjMatrix           : VIEWPROJECTION;
float elapsed_time : ELAPSEDTIME;
//ʱ��
float ftime : TIME<bool SyncInEditMode = true; > ;
float stime : TIME<bool SyncInEditMode = false; > ;



// ��Ļ��С
float2 ViewportSize : VIEWPORTPIXELSIZE;
static float ViewportAspect = ViewportSize.x / ViewportSize.y;


//����Halton���У��������ɾ���Jitter���ͶӰ����
static float GetHalton(int index, int radix) {
    float result = 0.0f;
    float fraction = 1.0f / radix;
    while (index > 0) {
        result += (index % radix) * fraction;

        index /= radix;
        fraction /= radix;
    }
    return result;
}

static float2 CalculateJitter(int frameIndex) {
    float jitterX = GetHalton((frameIndex % 1023) + 1, 2) - 0.5f;
    float jitterY = GetHalton((frameIndex % 1023) + 1, 3) - 0.5f;

    return float2(jitterX, jitterY);
}

static float4x4 CalculateJitterProjMatrix(float jitterScale = 1.0f) {
    float4x4 mat = ProjectionMatrix;
    int taaFrameIndex = ftime * elapsed_time;

    float actualWidth = ViewportSize.x;
    float actualHeight = ViewportSize.y;

    float2 jitter = CalculateJitter(taaFrameIndex) * jitterScale;

    mat[0][2] += jitter.x * (2.0f / actualWidth);
    mat[1][2] += jitter.y * (2.0f / actualHeight);

    return mul(WorldViewMatrix, mat);
}



bool use_texture;  //��������

// ������ɫ
float4 MaterialDiffuse   : DIFFUSE  < string Object = "Geometry"; >;


#if TRANS_TEXTURE!=0
    // ��������
    texture ObjectTexture: MATERIALTEXTURE;
    sampler ObjTexSampler = sampler_state
    {
        texture = <ObjectTexture>;
        MINFILTER = LINEAR;
        MAGFILTER = LINEAR;
    };
    
    
    // ���ڲ�����MMDԭʼsampler������������ɾ����
    sampler MMDSamp0 : register(s0);
    sampler MMDSamp1 : register(s1);
    sampler MMDSamp2 : register(s2);
    
#endif



//��߿ɴﵽ26�򶥵�
#define VPBUF_WIDTH  512
#define VPBUF_HEIGHT 512

//�������껺������С
static float2 VPBufSize = float2(VPBUF_WIDTH, VPBUF_HEIGHT);

static float2 VPBufOffset = float2(0.5 / VPBUF_WIDTH, 0.5 / VPBUF_HEIGHT);


//��¼ÿ���������������
texture DepthBuffer : RenderDepthStencilTarget <
   int Width=VPBUF_WIDTH;
   int Height=VPBUF_HEIGHT;
    string Format = "D24S8";
>;
texture VertexPosBufTex : RenderColorTarget
<
    int Width=VPBUF_WIDTH;
    int Height=VPBUF_HEIGHT;
    bool AntiAlias = false;
    int Miplevels = 1;
    string Format="A32B32G32R32F";
>;
sampler VertexPosBuf = sampler_state
{
   Texture = (VertexPosBufTex);
   ADDRESSU = CLAMP;
   ADDRESSV = CLAMP;
   MAGFILTER = NONE;
   MINFILTER = NONE;
   MIPFILTER = NONE;
};
texture VertexPosBufTex2 : RenderColorTarget
<
    int Width=VPBUF_WIDTH;
    int Height=VPBUF_HEIGHT;
    bool AntiAlias = false;
    int Miplevels = 1;
    string Format="A32B32G32R32F";
>;
sampler VertexPosBuf2 = sampler_state
{
   Texture = (VertexPosBufTex2);
   ADDRESSU = CLAMP;
   ADDRESSV = CLAMP;
   MAGFILTER = NONE;
   MINFILTER = NONE;
   MIPFILTER = NONE;
};
texture VertexPosBufTex3 : RenderColorTarget
<
    int Width = VPBUF_WIDTH;
    int Height = VPBUF_HEIGHT;
    bool AntiAlias = false;
    int Miplevels = 1;
    string Format = "A32B32G32R32F";
> ;
sampler VertexPosBuf3 = sampler_state
{
    Texture = (VertexPosBufTex3);
    ADDRESSU = CLAMP;
    ADDRESSV = CLAMP;
    MAGFILTER = NONE;
    MINFILTER = NONE;
    MIPFILTER = NONE;
};

//��¼������ͼͶӰ�����

#define INFOBUFSIZE 16

texture DepthBufferMB : RenderDepthStencilTarget <
   int Width=INFOBUFSIZE;
   int Height=1;
    string Format = "D24S8";
>;
texture MatrixBufTex : RenderColorTarget
<
    int Width=INFOBUFSIZE;
    int Height=1;
    bool AntiAlias = false;
    int Miplevels = 1;
    string Format="A32B32G32R32F";
>;

float4 MatrixBufArray[INFOBUFSIZE] : TEXTUREVALUE <
    string TextureName = "MatrixBufTex";
>;

//��һ֡���������
static float4x4 lastWorldMatrix = float4x4(MatrixBufArray[0], MatrixBufArray[1], MatrixBufArray[2], MatrixBufArray[3]);

//��һ֡����ͼͶӰ����
static float4x4 lastViewMatrix = float4x4(MatrixBufArray[4], MatrixBufArray[5], MatrixBufArray[6], MatrixBufArray[7]);

static float4x4 lastMatrix = mul(lastWorldMatrix, lastViewMatrix);



//�Ƿ�Ϊ����֡
//���ϴε����𾭹�0.5s����ʱ�ж�Ϊ����ʾ
static float last_ftime = MatrixBufArray[8].y;
static float last_stime = MatrixBufArray[8].x;
static bool Appear = (abs(last_stime - stime) > 0.5);



   
struct SKINNING_INPUT{
    float4 Pos : POSITION;
    float2 Tex : TEXCOORD0;
    float4 AddUV1 : TEXCOORD1;
    float4 AddUV2 : TEXCOORD2;
    float4 AddUV3 : TEXCOORD3;
    int Index     : _INDEX;
};


////////////////////////////////////////////////////////////////////////////////////////////////
//ͨ�ú���

//����W����Ļ����ת��Ϊ����Ļ����
float2 ScreenPosRasterize(float4 ScreenPos){
    return ScreenPos.xy / ScreenPos.w;
    
}

//��ȡ�������껺����
float4 getVertexPosBuf(float index)
{
    float4 Color;
    float2 tpos = float2(index % VPBUF_WIDTH, trunc(index / VPBUF_WIDTH));
    tpos += float2(0.5, 0.5);
    tpos /= float2(VPBUF_WIDTH, VPBUF_HEIGHT);
    Color = tex2Dlod(VertexPosBuf2, float4(tpos,0,0));
    return Color;
}

////////////////////////////////////////////////////////////////////////////////////////////////

struct VS_OUTPUT
{
    float4 Pos        : POSITION;    // ͶӰ�任����
    float2 Tex        : TEXCOORD0;   // UV
    float4 LastPos    : TEXCOORD1;
    float4 CurrentPos : TEXCOORD2;
};

VS_OUTPUT Velocity_VS(SKINNING_INPUT IN , uniform bool useToon)
{
    VS_OUTPUT Out = (VS_OUTPUT)0;
    
    if(useToon){
        Out.LastPos = ClonePos(getVertexPosBuf((float)(IN.Index)));
    }
    
    float4 pos = IN.Pos;
    pos = ClonePos(pos);
    
    Out.CurrentPos = pos;
    
    Out.Pos = mul( pos, WorldViewProjMatrix );
    
    #if TRANS_TEXTURE!=0
        Out.Tex = IN.Tex; //����UV
    #endif
    
    return Out;
}


float4 Velocity_PS( VS_OUTPUT IN , uniform bool useToon , uniform bool isEdge) : COLOR0
{
    float4 ViewPos = mul( IN.CurrentPos, WorldViewProjMatrix );
    float4 lastPos;
    float alpha = MaterialDiffuse.a;
    if(useToon){
        lastPos = mul( IN.LastPos, lastMatrix );
    }else{
        lastPos = mul( IN.CurrentPos, lastMatrix ); 
    }
    
    //���
    float mb_depth = ViewPos.z;
    
    #if TRANS_TEXTURE!=0
        if(use_texture){
            alpha *= tex2D(ObjTexSampler,IN.Tex).a;
        }
    #endif
    
    //�����ٶ�
    float2 Velocity = ScreenPosRasterize(ViewPos) - ScreenPosRasterize(lastPos);
    if (length(Velocity) <= 0.001f){
        lastPos = mul(IN.CurrentPos, CalculateJitterProjMatrix(1.0f));
        Velocity = ScreenPosRasterize(ViewPos) - ScreenPosRasterize(lastPos);
    }
    
    //����ٶ���Ϊ��ɫ
    Velocity = Velocity + 0.5;
    
    alpha = (alpha >= TransparentThreshold) * (isEdge ? (1.0 / (length(Velocity) * 30)) : 1);
    
    float4 Color = float4(Velocity, mb_depth, alpha);
    
    return Color;
    
}


/////////////////////////////////////////////////////////////////////////////////////
//������Ϣ������

struct VS_OUTPUT2 {
    float4 Pos: POSITION;
    float2 texCoord: TEXCOORD0;
};


VS_OUTPUT2 DrawMatrixBuf_VS(float4 Pos: POSITION, float2 Tex: TEXCOORD) {
    VS_OUTPUT2 Out;
    
    Out.Pos = Pos;
    Out.texCoord = Tex;
    return Out;
}

float4 DrawMatrixBuf_PS(float2 texCoord: TEXCOORD0) : COLOR {
    
    int dindex = (int)((texCoord.x * INFOBUFSIZE) + 0.2); //������Ԫ���
    float4 Color;
    
    if(dindex < 4){
        Color = WorldMatrix[(int)dindex]; //��¼����
        
    }else if(dindex < 8){
        Color = ViewProjMatrix[(int)dindex - 4];
        
    }else{
        Color = float4(stime, ftime, 0.5, 1);
    }
    
    return Color;
}


/////////////////////////////////////////////////////////////////////////////////////
//�����������껺����

struct VS_OUTPUT3 {
    float4 Pos: POSITION;
    float4 BasePos: TEXCOORD0;
};

VS_OUTPUT3 DrawVertexBuf_VS(SKINNING_INPUT IN)
{
    VS_OUTPUT3 Out;
    
    float findex = (float)(IN.Index);
    float2 tpos = 0;
    tpos.x = modf(findex / VPBUF_WIDTH, tpos.y);
    tpos.y /= VPBUF_HEIGHT;
    
    //���������
    Out.Pos.xy = (tpos * 2 - 1) * float2(1,-1); //��������-��������ת��
    Out.Pos.zw = float2(0, 1);
    
    //���ݸ�������ɫ�����޹�դ��
    Out.BasePos = IN.Pos;
    
    return Out;
}

float4 DrawVertexBuf_PS( VS_OUTPUT3 IN ) : COLOR0
{
    //���������Ϊ��ɫ
    return IN.BasePos;
}

/////////////////////////////////////////////////////////////////////////////////////
//���ƶ������껺����

VS_OUTPUT2 CopyVertexBuf_VS(float4 Pos: POSITION, float2 Tex: TEXCOORD) {
   VS_OUTPUT2 Out;
  
   Out.Pos = Pos;
   Out.texCoord = Tex + VPBufOffset;
   return Out;
}

float4 CopyVertexBuf_PS(float2 texCoord: TEXCOORD0) : COLOR {
   return tex2D(VertexPosBuf, texCoord);
}

/////////////////////////////////////////////////////////////////////////////////////


float4 ClearColor = {0,0,0,0};
float ClearDepth  = 1.0;


// ������Ƽ���

stateblock PMD_State = stateblock_state
{
    
    DestBlend = InvSrcAlpha; SrcBlend = SrcAlpha; //ȡ���ӷ��ϳ�
    AlphaBlendEnable = false;
    AlphaTestEnable = true;
    
    VertexShader = compile vs_3_0 Velocity_VS(true);
    PixelShader  = compile ps_3_0 Velocity_PS(true, false);
};

stateblock Edge_State = stateblock_state
{
    
    DestBlend = InvSrcAlpha; SrcBlend = SrcAlpha; //ȡ���ӷ��ϳ�
    AlphaBlendEnable = false;
    AlphaTestEnable = true;
    
    VertexShader = compile vs_3_0 Velocity_VS(true);
    PixelShader  = compile ps_3_0 Velocity_PS(true, true);
};


stateblock Accessory_State = stateblock_state
{
    
    DestBlend = InvSrcAlpha; SrcBlend = SrcAlpha; //ȡ���ӷ��ϳ�
    AlphaBlendEnable = false;
    AlphaTestEnable = true;
    
    VertexShader = compile vs_3_0 Velocity_VS(false);
    PixelShader  = compile ps_3_0 Velocity_PS(false, false);
};

stateblock makeMatrixBufState = stateblock_state
{
    AlphaBlendEnable = false;
    AlphaTestEnable = false;
    VertexShader = compile vs_3_0 DrawMatrixBuf_VS();
    PixelShader  = compile ps_3_0 DrawMatrixBuf_PS();
};


stateblock makeVertexBufState = stateblock_state
{
    DestBlend = InvSrcAlpha; SrcBlend = SrcAlpha; //ȡ���ӷ��ϳ�
    FillMode = POINT;
    CullMode = NONE;
    ZEnable = false;
    AlphaBlendEnable = false;
    AlphaTestEnable = false;
    
    VertexShader = compile vs_3_0 DrawVertexBuf_VS();
    PixelShader  = compile ps_3_0 DrawVertexBuf_PS();
};

stateblock copyVertexBufState = stateblock_state
{
    AlphaBlendEnable = false;
    AlphaTestEnable = false;
    VertexShader = compile vs_3_0 CopyVertexBuf_VS();
    PixelShader  = compile ps_3_0 CopyVertexBuf_PS();
};

////////////////////////////////////////////////////////////////////////////////////////////////

technique MainTec0_0 < 
    string MMDPass = "object"; 
    bool UseToon = true;
    string Subset = "0"; 
    string Script =
        
        "RenderColorTarget=MatrixBufTex;"
        "RenderDepthStencilTarget=DepthBufferMB;"
        "Pass=DrawMatrixBuf;"
        
        "RenderColorTarget=VertexPosBufTex2;"
        "RenderDepthStencilTarget=DepthBuffer;"
        "Pass=CopyVertexBuf;"
        
        "RenderColorTarget=;"
        "RenderDepthStencilTarget=;"
        "LoopByCount=CloneCount;"
        "LoopGetIndex=CloneIndex;"
        "Pass=DrawObject;"
        "LoopEnd=;"
        
        "RenderColorTarget=VertexPosBufTex;"
        "RenderDepthStencilTarget=DepthBuffer;"
        "Pass=DrawVertexBuf;"
    ;
> {
    pass DrawMatrixBuf < string Script = "Draw=Buffer;";>   { StateBlock = (makeMatrixBufState); }
    pass DrawObject    < string Script = "Draw=Geometry;";> { StateBlock = (PMD_State);  }
    pass DrawVertexBuf < string Script = "Draw=Geometry;";> { StateBlock = (makeVertexBufState); }
    pass CopyVertexBuf < string Script = "Draw=Buffer;";>   { StateBlock = (copyVertexBufState); }
    
}

