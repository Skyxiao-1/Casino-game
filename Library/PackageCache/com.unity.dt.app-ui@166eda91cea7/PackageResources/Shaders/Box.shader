Shader "Hidden/App UI/Box"
{
    Properties
    {
        _Ratio("Ratio", Float) = 1.0
        _Rect("Rect", Vector) = (0,0,1,1)
        _Color("Color", Color) = (1,1,1,1)
        _BackgroundImage("Background Image", 2D) = "black" {}
        _BackgroundImageTransform("Background Image Transform", Vector) = (0,0,1,1)
        _BackgroundSize("Background Size", Int) = 0
        _Radiuses("Radiuses", Vector) = (0,0,0.5,0.25)
        _AA("Anti Aliasing", Float) = 0.0012
        _Phase("Phase", Vector) = (0,0,0,0)
        [Header(Border)]
        [Toggle(ENABLE_BORDER)] _EnableBorder("Enable", Float) = 1
        _BorderThickness("Border Thickness", Range(0,1)) = 0.012
        _BorderColor("Border Color", Color) = (1,1,1,1)
        _BorderStyle("Border Style", Int) = 0
        _BorderDotFactor("Border Dot Factor", Int) = 3
        _BorderSpeed("Border Speed", Float) = 0.0
        [Header(Shadow)]
        [Toggle(ENABLE_SHADOW)] _EnableShadow("Enable", Float) = 1
        _ShadowOffset("Shadow Offset", Vector) = (0.1, 0.1, 0.02, 0.005)
        _ShadowColor("Shadow Color", Color) = (0,0,0,1)
        _ShadowInset("Shadow Inset Mode", Int) = 0
        [Header(Outline)]
        [Toggle(ENABLE_OUTLINE)] _EnableOutline("Enable", Float) = 1
        _OutlineThickness("Outline Thickness", Range(0,1)) = 0.012
        _OutlineColor("Outline Color", Color) = (1,1,1,1)
        _OutlineOffset("Outline Offset", Range(0,1)) = 0.0
    }
    SubShader
    {
        ZTest Always
        Cull Off
        ZWrite Off

        HLSLINCLUDE

        #include "AppUI.hlsl"

        struct appdata
        {
            float4 vertex : POSITION;
            float2 uv : TEXCOORD0;
        };

        struct v2f
        {
            float2 uv : TEXCOORD0;
            float4 vertex : SV_POSITION;
        };

        float _Ratio;
        float4 _Rect;

        v2f vert (appdata v)
        {
            v2f o;
            o.vertex = UnityObjectToClipPos(v.vertex);
            o.uv = float2((v.uv.x - _Rect.x) * 1.0, ((1.0 - v.uv.y - _Rect.y) * 1.0) * _Ratio); // reverse the Y axis because UITK uses origin at top-left corner
            return o;
        }

        float4 _Radiuses;
        float _AA;

        ENDHLSL

        Pass
        {
            Name "Clear"
            Blend One Zero

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            half4 frag(v2f i) : SV_Target
            {
                // Output the clear color (0,0,0,0)
                return half4(0, 0, 0, 0);
            }
            ENDHLSL
        }

        Pass
        {
            Name "BoxShadows"
            Blend SrcAlpha OneMinusSrcAlpha

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_local __ ENABLE_SHADOW

            half4 _ShadowColor;
            float4 _ShadowOffset;
            int _ShadowInset;

            half4 frag (v2f i) : SV_Target
            {
                #if ENABLE_SHADOW
                if (_ShadowInset == 1)
                    return half4(0,0,0,0);
                // Find clip box mask
                const float2 spread = float2(_ShadowOffset.z, _ShadowOffset.z / _Ratio);
                const float2 boxClipSSize = _Rect.zw + _AA * 0.5;
                const float2 halfSize = float2(boxClipSSize.x, boxClipSSize.y * _Ratio) * 0.5;
                const float sd = roundedBoxSDF(i.uv, halfSize, _Radiuses.zywx);
                // Find rounded shadow box mask
                float radius = (_Radiuses.x + _Radiuses.y + _Radiuses.z + _Radiuses.w) * 0.25;
                const float shadowWidth = _Rect.z + spread.x * 2.0;
                const float shadowHeight = _Rect.w + spread.y * 2.0;
                radius *= min(shadowWidth / _Rect.z, shadowHeight / _Rect.w);
                radius = min(min(shadowWidth, shadowHeight) * 0.5, radius);
                float2 lower = (-_Rect.zw * 0.5) + _ShadowOffset.xy - spread;
                float2 upper = lower + float2(shadowWidth, shadowHeight);
                lower.y *= _Ratio;
                upper.y *= _Ratio;
                const float sigma = max(0.0001, _ShadowOffset.w);
                float shadow = roundedBoxShadow(lower, upper, i.uv, sigma, radius);
                // apply shadow box mask
                shadow *= boxShadow(lower, upper, i.uv, sigma);
                // apply clip box mask based on Inset value
                // if the pixel is inside the box, then shadow is smoothed with _AA
                const float outsetShadow = sd > 0. ? shadow : smoothstep(-_AA, 0., sd) * shadow;
                return half4(_ShadowColor.rgb, outsetShadow * _ShadowColor.a);
                #else
                return half4(0,0,0,0);
                #endif
            }
            ENDHLSL
        }

        Pass
        {
            Name "BackgroundColor"
            Blend SrcAlpha OneMinusSrcAlpha

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            float _BorderThickness;
            half4 _Color;

            half4 frag (v2f i) : SV_Target
            {
                const float2 rectSize = _Rect.zw;
                const float2 halfSize = float2(rectSize.x, rectSize.y * _Ratio) * 0.5;
                const float distanceWithoutBorder = roundedBoxSDF(i.uv, halfSize, _Radiuses.zywx);
                const float smoothedAlphaWithoutBorder = 1.0 - smoothstep(0.0, _AA, distanceWithoutBorder);
                return half4(_Color.rgb, _Color.a * smoothedAlphaWithoutBorder);
            }
            ENDHLSL
        }

        Pass
        {
            Name "BackgroundImage"
            Blend SrcAlpha OneMinusSrcAlpha

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            float _BorderThickness;
            sampler2D _BackgroundImage;
            float4 _BackgroundImageTransform;
            int _BackgroundSize;

            half4 frag (v2f i) : SV_Target
            {
                const float2 rectSize = _Rect.zw - _BorderThickness;
                const float2 halfSize = float2(rectSize.x, rectSize.y * _Ratio) * 0.5;
                const float distanceWithoutBorder = roundedBoxSDF(i.uv, halfSize, _Radiuses.zywx);
                const float smoothedAlphaWithoutBorder = 1.0 - smoothstep(0.0, _AA, distanceWithoutBorder);

                const float xMin = - _Rect.z * 0.5 + _BorderThickness;
                const float xMax = _Rect.z * 0.5 - _BorderThickness;
                const float yMin = - _Rect.w * 0.5 + _BorderThickness;
                const float yMax = _Rect.w * 0.5 - _BorderThickness;

                const float imgWidth = _BackgroundImageTransform.z;
                const float imgHeight = _BackgroundImageTransform.w;

                const float containerHeight = abs(yMax - yMin);
                const float containerWidth = abs(xMax - xMin);

                const float wRatio = containerWidth / imgWidth;
                const float hRatio = (containerHeight / imgHeight) * _Ratio;

                // background-size (cover, contain, stretch)
                float2 coverRatio = float2(max(wRatio, hRatio), max(wRatio, hRatio));
                float2 containRatio = float2(min(wRatio, hRatio), min(wRatio, hRatio));
                float2 stretch = float2(wRatio, hRatio);

                float2 mode = _BackgroundSize == 0 ? coverRatio : _BackgroundSize == 1 ? containRatio : stretch;
                float2 uvScale = float2(imgWidth, imgHeight) * mode;

                const float2 texcoord = (float2(i.uv.x, -i.uv.y) / uvScale) + 0.5;

                // background-repeat (no-repeat)
                clip(texcoord.x < 0 || texcoord.x > 1 || texcoord.y < 0 || texcoord.y > 1 ? -1 : 1);

                const half4 img = tex2D(_BackgroundImage, texcoord);
                return half4(img.rgb, img.a * smoothedAlphaWithoutBorder);
            }
            ENDHLSL
        }

        Pass
        {
            Name "InsetBoxShadows"
            Blend SrcAlpha OneMinusSrcAlpha

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_local __ ENABLE_SHADOW

            half4 _ShadowColor;
            float4 _ShadowOffset;
            int _ShadowInset;

            half4 frag (v2f i) : SV_Target
            {
                #if ENABLE_SHADOW
                if (_ShadowInset == 0)
                    return half4(0,0,0,0);
                // Find clip box mask
                const float2 spread = float2(_ShadowOffset.z, _ShadowOffset.z / _Ratio) * -1.0;
                const float2 boxClipSSize = _Rect.zw;
                const float2 halfSize = float2(boxClipSSize.x, boxClipSSize.y * _Ratio) * 0.5;
                const float sd = roundedBoxSDF(i.uv, halfSize, _Radiuses.zywx);
                // Find rounded shadow box mask
                float radius = (_Radiuses.x + _Radiuses.y + _Radiuses.z + _Radiuses.w) * 0.25;
                const float shadowWidth = _Rect.z + spread.x * 2.0;
                const float shadowHeight = _Rect.w + spread.y * 2.0;
                radius *= min(shadowWidth / _Rect.z, shadowHeight / _Rect.w);
                radius = min(min(shadowWidth, shadowHeight) * 0.5, radius);
                float2 lower = (-_Rect.zw * 0.5) + _ShadowOffset.xy - spread;
                float2 upper = lower + float2(shadowWidth, shadowHeight);
                lower.y *= _Ratio;
                upper.y *= _Ratio;
                const float sigma = max(0.0001, _ShadowOffset.w);
                float shadow = roundedBoxShadow(lower, upper, i.uv, sigma, radius);
                // apply shadow box mask
                shadow *= boxShadow(lower, upper, i.uv, sigma);
                // apply clip box mask based on Inset value
                const float insetShadow = (1.0 - shadow) * max(float(sd < 0.), 0.);
                return half4(_ShadowColor.rgb, insetShadow * _ShadowColor.a);
                #else
                return half4(0,0,0,0);
                #endif
            }
            ENDHLSL
        }

        Pass
        {
            Name "Border"
            Blend SrcAlpha OneMinusSrcAlpha

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_local __ ENABLE_BORDER

            float _BorderThickness;
            half4 _BorderColor;
            int _BorderStyle;
            int _BorderDotFactor;
            float _BorderSpeed;
            float4 _Phase;

            half4 frag (v2f i) : SV_Target
            {
                #if ENABLE_BORDER
                if (_BorderStyle <= 0 || _BorderThickness <= 0.0 || _BorderColor.a <= 0.0)
                    return half4(0,0,0,0);

                const float band = _BorderThickness * _BorderDotFactor;
                const float2 boxClipSSize = _Rect.zw;
                float2 halfSize = float2(boxClipSSize.x, boxClipSSize.y * _Ratio) * 0.5;
                float4 box = paBox(i.uv, halfSize - _Radiuses.x, _Radiuses.x, band);
                const float distance = box.w;
                float borderAlpha = 1.0 - smoothstep(0.0, _AA, distance);
                borderAlpha *= 1.0 - smoothstep(_BorderThickness - _AA, _BorderThickness, abs(distance));

                halfSize = float2(boxClipSSize.x - _BorderThickness, (boxClipSSize.y * _Ratio) - _BorderThickness ) * 0.5;
                box = paBox(i.uv, halfSize - (_Radiuses.x - (_BorderThickness * 0.5)), _Radiuses.x - (_BorderThickness * 0.5), band);

                float2 q = box.xy;
                q.y *= floor(box.z / band) * (band / box.z);
                q.y -= _Phase.y * _BorderSpeed;
                const float2 dotUV = frac(q / band + 0.5) - 0.5;
                const float dotLength = length(dotUV);

                if (_BorderStyle == 2) // Dotted
                {
                    const float dotSize = 0.52 / _BorderDotFactor;
                    borderAlpha *= 1.0 - smoothstep(dotSize - (_AA / band), dotSize, abs(dotLength));
                }
                else if (_BorderStyle == 3) // Dashed
                {
                    const float dotSize = 0.25;
                    borderAlpha *= smoothstep(dotSize - (_AA / band), dotSize, abs(dotLength));
                }

                return half4(_BorderColor.rgb, _BorderColor.a * borderAlpha);

                #else
                return half4(0,0,0,0);
                #endif
            }
            ENDHLSL
        }

        Pass
        {
            Name "Outline"
            Blend SrcAlpha OneMinusSrcAlpha

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_local __ ENABLE_OUTLINE

            float _OutlineThickness;
            float _OutlineOffset;
            half4 _OutlineColor;

            half4 frag (v2f i) : SV_Target
            {
                #if ENABLE_OUTLINE
                const float2 halfSize = float2(_Rect.z, _Rect.w * _Ratio) * 0.5;
                const float distance = roundedBoxSDF(i.uv, halfSize, _Radiuses.zywx);
                const float outerAlpha = 1.0 - smoothstep(_OutlineOffset, _OutlineOffset + _AA, distance);
                const float innerAlpha = 1.0 - smoothstep(_OutlineOffset - _OutlineThickness + _AA * 0.5, _OutlineOffset - _OutlineThickness, distance);
                return half4(_OutlineColor.rgb, _OutlineColor.a * min(innerAlpha, outerAlpha));
                #else
                return half4(0,0,0,0);
                #endif
            }
            ENDHLSL
        }
    }
}
