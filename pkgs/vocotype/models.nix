{ fetchurl, linkFarm }:
let
  # Revisions and checksums are from v5.0.9's native model-manager manifest.
  model =
    id: files:
    map (file: {
      name = "models/${id}/${file.name}";
      path = fetchurl {
        url = "https://modelscope.cn/models/${id}/resolve/${file.rev}/${file.name}";
        sha256 = file.hash;
      };
    }) files;
in
linkFarm "vocotype-models-5.0.9" (
  model "iic/speech_paraformer-large-contextual_asr_nat-zh-cn-16k-common-vocab8404-onnx" [
    {
      name = "am.mvn";
      rev = "1c4c4d2ee95dfc59aa7efa3bacce6b72af4622bc";
      hash = "29b3c740a2c0cfc6b308126d31d7f265fa2be74f3bb095cd2f143ea970896ae5";
    }
    {
      name = "configuration.json";
      rev = "1c4c4d2ee95dfc59aa7efa3bacce6b72af4622bc";
      hash = "6e4e5234d4f657eb5530fbda198915b9f219aedbaa13a7b59b62819f43022af3";
    }
    {
      name = "config.yaml";
      rev = "0e8b6a277734182ed17edb1302051dc40295622e";
      hash = "1d9057edeaba9e131cb98f26011606497cf3af187d8943525ddb5ee36c836b1b";
    }
    {
      name = "model_eb.onnx";
      rev = "8f0881c891ceba7360e215b04e54cad564a68c41";
      hash = "d31446a5af664291a2922cca253a4200a523f347d6fc3cb1bff356bf60a116b6";
    }
    {
      name = "model_quant.onnx";
      rev = "8f0881c891ceba7360e215b04e54cad564a68c41";
      hash = "f404e6eb532b54fd95761e2b4be4ed1998e8cff3cb3b930a9bee1f2d556e5035";
    }
    {
      name = "seg_dict";
      rev = "1c4c4d2ee95dfc59aa7efa3bacce6b72af4622bc";
      hash = "59a2ef803a3f1648ad03a2e1480db1c1ee0c0d7dc4ef4dbd16cea33944329022";
    }
    {
      name = "tokens.json";
      rev = "0e8b6a277734182ed17edb1302051dc40295622e";
      hash = "2b20c2b12572d682afff84ce1c8d560f67b8b32a4c1f21567411d141ed352127";
    }
  ]
  ++ model "iic/speech_paraformer-large_asr_nat-zh-cn-16k-common-vocab8404-online-onnx" [
    {
      name = "am.mvn";
      rev = "8379db60b12deddfd8ddc95350c2bbd8e058667c";
      hash = "29b3c740a2c0cfc6b308126d31d7f265fa2be74f3bb095cd2f143ea970896ae5";
    }
    {
      name = "configuration.json";
      rev = "8379db60b12deddfd8ddc95350c2bbd8e058667c";
      hash = "cbf1c4e973cbb914d5c3aa24dcb30468bccc3abef60c1b9f9bb28b1f75c81255";
    }
    {
      name = "config.yaml";
      rev = "3f52bb64b3b3a09c2c06ab6da22795d438e7c777";
      hash = "35e6bf41f8c7eaf9a0f787af7fdc8fc5ed75fa8009ade7d3c2f3ef5bce20c648";
    }
    {
      name = "decoder_quant.onnx";
      rev = "8379db60b12deddfd8ddc95350c2bbd8e058667c";
      hash = "9855f60417e6eccddc4c7340d448fe99e95be689cba6e76c5330aa653d430aea";
    }
    {
      name = "model_quant.onnx";
      rev = "8379db60b12deddfd8ddc95350c2bbd8e058667c";
      hash = "c008250f40abf9bfe1957cf98d47cc734d6da6ce7301de40c534b57f9b366336";
    }
    {
      name = "tokens.json";
      rev = "3f52bb64b3b3a09c2c06ab6da22795d438e7c777";
      hash = "2b20c2b12572d682afff84ce1c8d560f67b8b32a4c1f21567411d141ed352127";
    }
  ]
  ++ model "iic/speech_fsmn_vad_zh-cn-16k-common-onnx" [
    {
      name = "am.mvn";
      rev = "9e08ccbfe15c79d0f4b41247c5ed4266031ac362";
      hash = "6820fef9687708c4fc3fab2530179c8fcea6262daa25514380056cd8f6eb1754";
    }
    {
      name = "configuration.json";
      rev = "bdaa7c49489f31282c1c17a3b86e2c80e40f8d30";
      hash = "f62fcbcebbaade798714b34c521cad87d869ee6a327ceed948e01ff2336bbfc0";
    }
    {
      name = "config.yaml";
      rev = "60b33f725eb866acee2a4fce6f8d73ab4276ca6b";
      hash = "96dd96779c8200123ad15f5230783c862e8c99d1805e89c9394635514d5a243d";
    }
    {
      name = "model_quant.onnx";
      rev = "f436483dfd1bf3eb1b410133ff86ecc9e10abc4a";
      hash = "5289eb2aa3c9af2d7a4284bcfa7c3ceb81d360814ed4203239b6c5d0569da8a1";
    }
  ]
  ++ model "iic/punc_ct-transformer_zh-cn-common-vocab272727-onnx" [
    {
      name = "configuration.json";
      rev = "8297bd50cd5c29b53a51c661520e27d2faadc6f3";
      hash = "16097d3034818080e39331fa08909dffe75189f5c986f74155afd90b5f531ee4";
    }
    {
      name = "config.yaml";
      rev = "c9d8ba523014110650428e422a4975343193975c";
      hash = "a56ec10925b06fa976ad51af373396be2b13e1eb8dc62a5426b5adebaba7071d";
    }
    {
      name = "model_quant.onnx";
      rev = "8f239ff78c6267c4d859233e7eb3bbdb68c61824";
      hash = "e6cd8399bf7d0e75f8d9af4a107310e1968ecab1d50135e765b8f0265b27a83d";
    }
    {
      name = "tokens.json";
      rev = "c9d8ba523014110650428e422a4975343193975c";
      hash = "c960ab87bccea4aa15cf49a59f71973c2c330b46668048cd8da253749ec71ee3";
    }
  ]
)
