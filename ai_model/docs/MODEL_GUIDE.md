# AI Model Selection Guide

## Introduction

This guide helps you choose the right AI model for your specific needs and hardware constraints. Whether you're generating code, having conversations, analyzing documents, or solving complex problems, selecting the appropriate model can significantly impact both performance and quality.

### Quick Decision Tree

```
Do you have 48GB+ RAM?
├─ Yes → llama3.3:70b-instruct-q4_K_M (best overall quality)
│   └─ For code → codestral:22b-v0.1-q8_0
└─ No → Do you have 32GB+ RAM?
    ├─ Yes → For general use: llama3.2:11b-instruct-q8_0
    │   ├─ For code → codestral:22b-v0.1-q8_0
    │   └─ For large docs → gemma4:31b-it-q8_0
    └─ No (16GB RAM) → llama3.2:3b-instruct-q8_0 (fast, efficient)
```

---

## Model Selection by Task Type

| Task Type | Recommended Model | Rationale |
|-----------|------------------|-----------|
| **Code Generation** | `codestral:22b-v0.1-q8_0` | Purpose-built for code, excellent at understanding context and generating accurate code across multiple languages |
| **General Chat** | `llama3.3:70b-instruct-q4_K_M` | Best overall quality, natural conversation, strong reasoning |
| **Fast Responses** | `llama3.2:3b-instruct-q8_0` | Near-instant responses, ideal for simple queries and quick iterations |
| **Large Documents** | `gemma4:31b-it-q8_0` | 256K token context window, can process entire codebases or long documents |
| **Reasoning/Math** | `phi4:14b-q8_0` | Specialized in logical reasoning, mathematics, and complex problem-solving |
| **Balanced Performance** | `llama3.2:11b-instruct-q8_0` | Good quality with moderate resource requirements |
| **Creative Writing** | `llama3.3:70b-instruct-q4_K_M` | Rich vocabulary, coherent long-form content |
| **Data Analysis** | `gemma4:31b-it-q8_0` | Strong analytical capabilities, large context for datasets |

---

## RAM Requirements Table

| Model | Model Size | Min RAM | Recommended RAM | Use Case |
|-------|-----------|---------|-----------------|----------|
| **llama3.3:70b-instruct-q4_K_M** | ~42GB | 48GB | 64GB+ | Best overall quality, natural language understanding |
| **codestral:22b-v0.1-q8_0** | ~24GB | 32GB | 48GB+ | Code generation and understanding |
| **gemma4:31b-it-q8_0** | ~34GB | 40GB | 48GB+ | Large context window (256K), document analysis |
| **llama3.2:11b-instruct-q8_0** | ~12GB | 24GB | 32GB+ | Balanced performance and efficiency |
| **phi4:14b-q8_0** | ~14GB | 24GB | 32GB+ | Reasoning, math, logical problems |
| **llama3.2:3b-instruct-q8_0** | ~3.5GB | 16GB | 16GB+ | Fast responses, resource-constrained environments |
| **qwen2.5:7b-instruct-q8_0** | ~7.7GB | 16GB | 24GB+ | Multilingual support, good general performance |

**Note:** These are approximate values. Actual RAM usage depends on context length, concurrent operations, and system overhead. Always leave 4-8GB free for the operating system and other applications.

---

## Quantization Explained

### What is Quantization?

Quantization reduces model size by using fewer bits to represent each weight parameter. This allows larger models to run on consumer hardware with minimal quality loss.

**Quantization Formats:**

- **FP16 (original)**: 16 bits per weight
  - Full precision, largest size
  - ~100% quality (baseline)

- **Q8_0**: 8 bits per weight
  - 50% of original size
  - 99% quality retention
  - Negligible performance difference

- **Q4_K_M**: 4 bits per weight
  - 25% of original size
  - 95-98% quality retention
  - Allows running much larger models

### When to Use Each

**Q8_0 Quantization** - Maximum Quality
- You have sufficient RAM for the model
- Quality is paramount
- Working on precision-critical tasks (code, math, reasoning)
- Recommended for models up to 22B parameters on 32GB+ RAM

**Q4_K_M Quantization** - Maximum Accessibility
- You need to fit larger models in limited RAM
- Want the capabilities of a 70B model on 48GB RAM
- Acceptable 2-5% quality trade-off for 2x size reduction
- Recommended for large models (70B) on consumer hardware

### Trade-offs Visualization

```
Size vs Quality Trade-off:

FP16:     ████████████████ (100% size, 100% quality)
Q8_0:     ████████         (50% size, 99% quality)    ← Sweet spot for most users
Q4_K_M:   ████             (25% size, 95-98% quality) ← Enables 70B models
Q2_K:     ██               (12.5% size, 85-90% quality) ⚠️ Not recommended
```

**Practical Example:**
- `llama3.3:70b-instruct` (FP16): ~140GB → Requires expensive workstation
- `llama3.3:70b-instruct-q8_0`: ~70GB → Requires 80GB+ RAM (still expensive)
- `llama3.3:70b-instruct-q4_K_M`: ~42GB → Runs on 48GB RAM (accessible)

---

## Decision Tree (Detailed)

### Step 1: Assess Your Hardware

**Check your available RAM:**
```bash
# macOS
sysctl hw.memsize | awk '{print $2/1073741824 " GB"}'

# Linux
free -h | awk '/^Mem:/ {print $2}'
```

### Step 2: Identify Your Primary Use Case

#### For Code Development
```
48GB+ RAM → codestral:22b-v0.1-q8_0 (maximum quality)
32GB RAM  → codestral:22b-v0.1-q8_0 (balanced)
16GB RAM  → llama3.2:3b-instruct-q8_0 (fast iteration)
```

#### For General Assistance
```
64GB+ RAM → llama3.3:70b-instruct-q4_K_M (best overall)
48GB RAM  → llama3.3:70b-instruct-q4_K_M (excellent)
32GB RAM  → llama3.2:11b-instruct-q8_0 (very good)
16GB RAM  → llama3.2:3b-instruct-q8_0 (efficient)
```

#### For Document Analysis
```
48GB+ RAM → gemma4:31b-it-q8_0 (256K context)
32GB RAM  → gemma4:31b-it-q8_0 (large documents)
16GB RAM  → qwen2.5:7b-instruct-q8_0 (smaller documents)
```

#### For Reasoning & Math
```
32GB+ RAM → phi4:14b-q8_0 (specialized reasoning)
16GB RAM  → llama3.2:3b-instruct-q8_0 (basic reasoning)
```

### Step 3: Consider Your Speed Requirements

- **Speed Priority**: Choose smaller models (3B-7B)
- **Quality Priority**: Choose larger models (22B-70B)
- **Balanced**: Choose mid-size models (11B-14B)

---

## Model Families Overview

### Llama Family (Meta)

**Models Available:**
- `llama3.3:70b-instruct-q4_K_M` (42GB)
- `llama3.2:11b-instruct-q8_0` (12GB)
- `llama3.2:3b-instruct-q8_0` (3.5GB)

**Strengths:**
- Excellent general-purpose performance
- Natural, coherent responses
- Strong reasoning capabilities
- Well-documented and widely supported
- Good at following instructions
- Balanced performance across tasks

**Weaknesses:**
- Not specialized for any particular task
- 70B model requires significant RAM
- Smaller models (3B) may struggle with complex reasoning

**Best Use Cases:**
- General conversation and assistance
- Creative writing
- Question answering
- Content generation
- When you need reliable, well-rounded performance

**Recommended For:**
- Primary assistant for most users
- Default choice when uncertain
- Users with varying task requirements

---

### Mistral/Codestral Family (Mistral AI)

**Models Available:**
- `codestral:22b-v0.1-q8_0` (24GB)
- `mistral-nemo:12b-instruct-q8_0` (13GB)

**Strengths:**
- **Codestral**: Purpose-built for code generation
- Excellent at understanding programming context
- Supports 80+ programming languages
- Strong at code completion and refactoring
- Fast inference speed
- Efficient architecture

**Weaknesses:**
- Codestral is specialized, less optimal for general chat
- Smaller model selection compared to Llama
- May be less creative in non-code tasks

**Best Use Cases:**
- Software development
- Code review and debugging
- API integration
- Script writing
- Technical documentation
- Refactoring and optimization

**Recommended For:**
- Developers and engineers
- Code-heavy workflows
- Users who prioritize code quality
- Technical writing and documentation

---

### Phi Family (Microsoft)

**Models Available:**
- `phi4:14b-q8_0` (14GB)

**Strengths:**
- Exceptional reasoning capabilities
- Strong mathematical problem-solving
- Logical analysis and deduction
- Efficient parameter usage
- Research-focused design
- Good at step-by-step explanations

**Weaknesses:**
- Smaller context window than competitors
- May be less creative in open-ended tasks
- Less general-purpose than Llama
- Fewer available model sizes

**Best Use Cases:**
- Mathematical problem-solving
- Logical reasoning tasks
- Scientific analysis
- Educational content
- Structured problem-solving
- Algorithm design and analysis

**Recommended For:**
- Students and educators
- Researchers
- Data scientists
- Users with reasoning-heavy workloads
- Math and science applications

---

### Gemma Family (Google)

**Models Available:**
- `gemma4:31b-it-q8_0` (34GB)

**Strengths:**
- **Massive 256K token context window**
- Can process entire codebases
- Excellent for long-document analysis
- Strong analytical capabilities
- Good general performance
- Research-backed architecture

**Weaknesses:**
- Requires significant RAM (40GB+)
- Overkill for simple queries
- Large context window can slow inference
- Limited model size options

**Best Use Cases:**
- Analyzing large codebases
- Processing long documents
- Multi-file code understanding
- Document summarization
- Research paper analysis
- Comprehensive code reviews

**Recommended For:**
- Users working with large projects
- Document analysis workflows
- Codebase understanding and migration
- Research and analysis tasks
- Users with 48GB+ RAM

---

### Qwen Family (Alibaba)

**Models Available:**
- `qwen2.5:7b-instruct-q8_0` (7.7GB)

**Strengths:**
- Strong multilingual support
- Excellent at Asian languages
- Good balance of size and performance
- Fast inference
- Efficient architecture
- Broad task coverage

**Weaknesses:**
- Less well-known in Western markets
- Smaller community support
- May not excel at specialized tasks

**Best Use Cases:**
- Multilingual applications
- Translation and localization
- General assistance with language diversity
- Resource-constrained environments
- Fast, efficient general use

**Recommended For:**
- Multilingual users
- International projects
- Users needing good performance on modest hardware
- Translation workflows

---

## Performance Comparison

### Inference Speed (Approximate tokens/second on M3 Max 64GB)

| Model | Speed | Quality | RAM | Best For |
|-------|-------|---------|-----|----------|
| llama3.2:3b-instruct-q8_0 | 90 t/s | Good | 16GB | Fast iteration |
| qwen2.5:7b-instruct-q8_0 | 65 t/s | Very Good | 16GB | Balanced |
| llama3.2:11b-instruct-q8_0 | 45 t/s | Very Good | 24GB | General use |
| phi4:14b-q8_0 | 40 t/s | Excellent (reasoning) | 24GB | Math/logic |
| codestral:22b-v0.1-q8_0 | 30 t/s | Excellent (code) | 32GB | Development |
| gemma4:31b-it-q8_0 | 22 t/s | Excellent | 40GB | Large context |
| llama3.3:70b-instruct-q4_K_M | 12 t/s | Outstanding | 48GB | Best quality |

**Note:** Actual speeds vary based on hardware, context length, and system load.

---

## Common Scenarios

### Scenario 1: Full-Stack Developer (32GB RAM)

**Primary Model:** `codestral:22b-v0.1-q8_0`
- Use for code generation, debugging, refactoring

**Secondary Model:** `llama3.2:11b-instruct-q8_0`
- Use for documentation, planning, general questions

**Why:** Maximizes code quality while maintaining flexibility for other tasks.

---

### Scenario 2: Content Creator (48GB RAM)

**Primary Model:** `llama3.3:70b-instruct-q4_K_M`
- Use for writing, brainstorming, creative work

**Secondary Model:** `llama3.2:3b-instruct-q8_0`
- Use for quick questions, rapid iteration

**Why:** Best quality for creative content with fast model for quick checks.

---

### Scenario 3: Researcher/Student (32GB RAM)

**Primary Model:** `phi4:14b-q8_0`
- Use for math, reasoning, problem-solving

**Secondary Model:** `gemma4:31b-it-q8_0` (if 40GB available)
- Use for analyzing papers and large documents

**Why:** Specialized reasoning model with large context for research.

---

### Scenario 4: Budget/Resource-Constrained (16GB RAM)

**Primary Model:** `llama3.2:3b-instruct-q8_0`
- Use for general tasks, fast responses

**Alternative:** `qwen2.5:7b-instruct-q8_0`
- Use when you need better quality and can spare the RAM

**Why:** Efficient models that work well on limited hardware.

---

## Tips for Optimal Performance

### 1. Model Warm-up
First query after loading a model is slower. Consider a warm-up query:
```bash
echo "Hello" | ollama run your-model
```

### 2. Context Management
- Larger contexts use more RAM and slow inference
- Clear context periodically for long sessions
- Use streaming mode for better perceived performance

### 3. Concurrent Models
- Running multiple models simultaneously multiplies RAM usage
- Unload unused models: `ollama stop model-name`
- Monitor RAM: `ollama ps`

### 4. Hardware Optimization
- Close unnecessary applications
- Ensure adequate cooling (thermal throttling affects performance)
- Use SSD for model storage (faster loading)

### 5. Model Selection Strategy
- Start with smaller models for prototyping
- Use larger models for final/production work
- Switch models based on task complexity

---

## Frequently Asked Questions

**Q: Can I run multiple models at once?**
A: Yes, but RAM usage multiplies. Running a 22B and 11B model requires RAM for both plus overhead.

**Q: What happens if I run out of RAM?**
A: System will swap to disk, causing severe slowdown. Choose smaller models or close other applications.

**Q: Should I use Q8_0 or Q4_K_M?**
A: Q8_0 if you have RAM to spare, Q4_K_M if you need to fit larger models.

**Q: How do I switch models?**
A: Simply use `ollama run different-model` - models are loaded on demand.

**Q: Can I fine-tune these models?**
A: Yes, but that's beyond the scope of this guide. See Ollama documentation for fine-tuning.

**Q: Which model is closest to ChatGPT?**
A: `llama3.3:70b-instruct-q4_K_M` offers comparable quality for most tasks.

**Q: Why are inference speeds so variable?**
A: Speed depends on prompt length, context size, hardware, and system load.

---

## Conclusion

Model selection is a balance between:
- **Available RAM** - Hardware constraints
- **Task requirements** - What you need to accomplish
- **Speed vs Quality** - Response time vs output quality
- **Specialization** - General purpose vs task-specific

**General Recommendations:**
- **Best Overall:** `llama3.3:70b-instruct-q4_K_M` (if 48GB+ RAM)
- **Best Value:** `llama3.2:11b-instruct-q8_0` (32GB RAM)
- **Best Efficiency:** `llama3.2:3b-instruct-q8_0` (16GB RAM)
- **Best for Code:** `codestral:22b-v0.1-q8_0` (32GB RAM)
- **Best for Docs:** `gemma4:31b-it-q8_0` (40GB+ RAM)
- **Best for Math:** `phi4:14b-q8_0` (24GB RAM)

Start with the recommended model for your RAM tier, then adjust based on your specific needs and performance observations.

---

*Last Updated: 2026-04-07*
*For updates and additional models, check the Ollama model library: https://ollama.com/library*
