# Rebuilds Resources/AIConfig/IntentEncoder.mlpackage and vocab.txt: AI Config's semantic model.
# sentence-transformers/paraphrase-MiniLM-L3-v2 (Apache-2.0, 17M parameters), mean-pooled and normalized inside the
# model, 64 tokens, float16. Picked over the macOS sentence embedding (15/30), NLI models (≤20/30), Qwen 0.5–1.7B
# (≤13/30) and larger MiniLM/BGE models on held-out paraphrases.
#
#   uv venv -p 3.12 /tmp/ml && VIRTUAL_ENV=/tmp/ml uv pip install "torch==2.5.1" "transformers==4.44.2" "coremltools==8.3.0" "numpy<2"
#   /tmp/ml/bin/python scripts/make_intent_encoder.py
# (Newer transformers versions trace into ops coremltools can't convert.)
import shutil, torch, numpy as np, coremltools as ct
from transformers import AutoTokenizer, AutoModel

NAME, L, OUT = "sentence-transformers/paraphrase-MiniLM-L3-v2", 64, "Resources/AIConfig"
tok = AutoTokenizer.from_pretrained(NAME)
bert = AutoModel.from_pretrained(NAME, torchscript=True).eval()

class Embed(torch.nn.Module):
    def __init__(self, b): super().__init__(); self.b = b
    def forward(self, ids, mask):
        h = self.b(input_ids=ids, attention_mask=mask)[0]
        m = mask.unsqueeze(-1).float()
        return torch.nn.functional.normalize((h * m).sum(1) / m.sum(1).clamp(min=1e-9), dim=-1)

ex = tok("hello world", padding="max_length", max_length=L, return_tensors="pt")
traced = torch.jit.trace(Embed(bert).eval(), (ex.input_ids.int(), ex.attention_mask.int()))
ml = ct.convert(traced, inputs=[ct.TensorType(name="input_ids", shape=(1, L), dtype=np.int32),
                                ct.TensorType(name="attention_mask", shape=(1, L), dtype=np.int32)],
                outputs=[ct.TensorType(name="embedding")], compute_precision=ct.precision.FLOAT16,
                minimum_deployment_target=ct.target.macOS14)
ml.short_description = "paraphrase-MiniLM-L3-v2 (Apache-2.0): sentence → 384-d unit vector, mean-pooled. 64 tokens."
shutil.rmtree(f"{OUT}/IntentEncoder.mlpackage", ignore_errors=True)
ml.save(f"{OUT}/IntentEncoder.mlpackage")
shutil.copy(tok.save_pretrained("/tmp/intent-tok")[0].replace("tokenizer_config.json", "vocab.txt"), f"{OUT}/vocab.txt")
