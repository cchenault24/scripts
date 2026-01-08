#!/usr/bin/env python3
"""
Ollama Optimization Proxy Server
Intercepts Continue.dev requests and applies optimizations
"""
import http.server
import socketserver
import json
import urllib.request
import urllib.parse
import sys
import os
import subprocess
import time
import re

OLLAMA_PORT = int(os.environ.get('OLLAMA_PORT', '11434'))
PROJECT_DIR = os.environ.get('PROJECT_DIR', '/Users/chenaultfamily/Documents/coding/scripts/ai_model')
OLLAMA_BASE = f'http://localhost:{OLLAMA_PORT}'

# Advanced optimization flags (can be set via environment variables)
ENABLE_PROMPT_OPTIMIZATION = os.environ.get('ENABLE_PROMPT_OPTIMIZATION', '1') == '1'
ENABLE_CONTEXT_COMPRESSION = os.environ.get('ENABLE_CONTEXT_COMPRESSION', '1') == '1'
ENABLE_ENSEMBLE = os.environ.get('ENABLE_ENSEMBLE', '0') == '1'  # Off by default (slower but better quality)

def ensure_optimization_services_running():
    """Ensure memory monitor and queue processor are running (unless disabled)"""
    import os
    import subprocess
    import time
    
    pid_dir = os.path.expanduser("~/.local-llm-setup/pids")
    os.makedirs(pid_dir, exist_ok=True)
    
    # Check disable flag first
    disabled_flag = os.path.expanduser("~/.local-llm-setup/optimizations.disabled")
    if os.path.exists(disabled_flag):
        print("Auto-start is disabled, skipping service startup")
        return
    
    # Check if memory monitor is running
    memory_monitor_pid_file = os.path.join(pid_dir, "memory_monitor.pid")
    memory_monitor_running = False
    if os.path.exists(memory_monitor_pid_file):
        try:
            with open(memory_monitor_pid_file, 'r') as f:
                pid = int(f.read().strip())
                os.kill(pid, 0)  # Check if process exists (raises OSError if not)
                memory_monitor_running = True
        except (OSError, ValueError):
            # Process doesn't exist, remove stale PID file
            try:
                os.remove(memory_monitor_pid_file)
            except:
                pass
    
    # Check if queue processor is running
    queue_processor_pid_file = os.path.join(pid_dir, "queue_processor.pid")
    queue_processor_running = False
    if os.path.exists(queue_processor_pid_file):
        try:
            with open(queue_processor_pid_file, 'r') as f:
                pid = int(f.read().strip())
                os.kill(pid, 0)
                queue_processor_running = True
        except (OSError, ValueError):
            # Process doesn't exist, remove stale PID file
            try:
                os.remove(queue_processor_pid_file)
            except:
                pass
    
    # Start missing services
    if not memory_monitor_running or not queue_processor_running:
        # Source optimization.sh and start services
        bash_script = f'''
export PROJECT_DIR="{PROJECT_DIR}"
source "{PROJECT_DIR}/lib/constants.sh"
source "{PROJECT_DIR}/lib/logger.sh"
source "{PROJECT_DIR}/lib/ui.sh"
source "{PROJECT_DIR}/lib/hardware.sh"
source "{PROJECT_DIR}/lib/ollama.sh"
source "{PROJECT_DIR}/lib/models.sh"
source "{PROJECT_DIR}/lib/optimization.sh"

PID_DIR="{pid_dir}"
mkdir -p "$PID_DIR"

'''
        
        if not memory_monitor_running:
            bash_script += '''
# Start memory monitor
if [[ ! -f "$PID_DIR/memory_monitor.pid" ]] || ! kill -0 "$(cat "$PID_DIR/memory_monitor.pid" 2>/dev/null)" 2>/dev/null; then
  (
    source "$PROJECT_DIR/lib/optimization.sh"
    monitor_memory_pressure 60 85
  ) > "$HOME/.local-llm-setup/memory_monitor.log" 2>&1 &
  echo $! > "$PID_DIR/memory_monitor.pid"
fi
'''
        
        if not queue_processor_running:
            bash_script += '''
# Start queue processor
if [[ ! -f "$PID_DIR/queue_processor.pid" ]] || ! kill -0 "$(cat "$PID_DIR/queue_processor.pid" 2>/dev/null)" 2>/dev/null; then
  (
    source "$PROJECT_DIR/lib/optimization.sh"
    while true; do
      process_request_queue 5 10
      sleep 5
    done
  ) > "$HOME/.local-llm-setup/queue_processor.log" 2>&1 &
  echo $! > "$PID_DIR/queue_processor.pid"
fi
'''
        
        # Execute bash script to start services
        try:
            proc = subprocess.Popen(
                ['/bin/bash', '-c', bash_script],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL
            )
            # Give services a moment to start
            time.sleep(1)
            # Check if process is still running (bash script should have started background processes)
            if proc.poll() is None or proc.returncode == 0:
                print("Started optimization services (memory monitor and queue processor)")
            else:
                print("Warning: Service startup script may have failed")
        except Exception as e:
            print(f"Warning: Failed to start optimization services: {e}")
            # Continue anyway - proxy can run without these services

class OptimizationProxyHandler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        """Handle POST requests (Ollama API calls)"""
        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length)
        
        try:
            request_data = json.loads(body.decode('utf-8'))
            model = request_data.get('model', '')
            prompt = request_data.get('prompt', '')
            context = request_data.get('context', [])  # May contain context array
            
            # Determine task type from prompt/context
            task_type = self.detect_task_type(prompt, request_data)
            
            # Optimize prompt for better results
            if ENABLE_PROMPT_OPTIMIZATION:
                prompt = self.optimize_prompt(prompt, task_type, model)
            
            # Compress context if it's too large
            if ENABLE_CONTEXT_COMPRESSION and context:
                context = self.compress_context_if_needed(context, request_data)
                request_data['context'] = context
            
            # Apply optimizations via bash functions
            optimized_model = self.route_to_optimal_model(model, task_type)
            optimized_params = self.get_optimized_params(optimized_model, task_type, request_data)
            
            # Use ensemble if enabled (for complex tasks - slower but higher quality)
            use_ensemble = ENABLE_ENSEMBLE and task_type in ['refactoring', 'complex', 'analysis']
            
            # Forward to Ollama with optimizations
            ollama_request = request_data.copy()
            ollama_request['prompt'] = prompt
            ollama_request['model'] = optimized_model
            if 'options' not in ollama_request:
                ollama_request['options'] = {}
            ollama_request['options'].update(optimized_params)
            
            # Track performance start
            start_time = time.time()
            
            # Execute with ensemble if enabled, otherwise normal request
            if use_ensemble:
                response_data = self.execute_ensemble_request(ollama_request, task_type, optimized_model)
            else:
                # Forward to Ollama
                ollama_url = f'{OLLAMA_BASE}{self.path}'
                req = urllib.request.Request(ollama_url, 
                                            data=json.dumps(ollama_request).encode('utf-8'),
                                            headers={'Content-Type': 'application/json'})
                
                try:
                    with urllib.request.urlopen(req, timeout=300) as response:
                        response_data = response.read()
                except Exception as e:
                    self.send_error(500, f"Ollama request failed: {str(e)}")
                    return
            
            duration = time.time() - start_time
            
            # Extract token count from response
            try:
                resp_json = json.loads(response_data.decode('utf-8'))
                tokens = len(resp_json.get('response', '').split()) if 'response' in resp_json else 0
            except:
                tokens = 0
            
            # Track performance
            self.track_performance(optimized_model, task_type, duration, tokens)
            
            # Track prompt performance for learning
            if ENABLE_PROMPT_OPTIMIZATION:
                self.track_prompt_performance(prompt, task_type, duration, tokens)
            
            # Return response
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(response_data)
                
        except Exception as e:
            self.send_error(400, f"Request processing failed: {str(e)}")
    
    def do_GET(self):
        """Forward GET requests directly to Ollama"""
        ollama_url = f'{OLLAMA_BASE}{self.path}'
        try:
            with urllib.request.urlopen(ollama_url, timeout=10) as response:
                self.send_response(response.status)
                for header, value in response.headers.items():
                    if header.lower() not in ['connection', 'transfer-encoding']:
                        self.send_header(header, value)
                self.end_headers()
                self.wfile.write(response.read())
        except Exception as e:
            self.send_error(500, f"Ollama request failed: {str(e)}")
    
    def detect_task_type(self, prompt, request_data):
        """Detect task type from prompt content"""
        prompt_lower = prompt.lower()
        
        # Check for autocomplete patterns
        if any(word in prompt_lower for word in ['autocomplete', 'complete', 'suggest', 'tab']):
            return 'autocomplete'
        # Check for refactoring patterns
        elif any(word in prompt_lower for word in ['refactor', 'refactoring', 'restructure', 'restructure']):
            return 'refactoring'
        # Check for code review patterns
        elif any(word in prompt_lower for word in ['review', 'check', 'analyze code', 'debug']):
            return 'code-review'
        # Check for complex patterns
        elif any(word in prompt_lower for word in ['complex', 'multi-file', 'architecture', 'large']):
            return 'complex'
        else:
            return 'coding'
    
    def route_to_optimal_model(self, requested_model, task_type):
        """Route to optimal model using orchestration"""
        try:
            # Call route_task_to_model via bash
            result = subprocess.run(
                ['bash', '-c', f'''
                export PROJECT_DIR="{PROJECT_DIR}"
                source "{PROJECT_DIR}/lib/constants.sh"
                source "{PROJECT_DIR}/lib/logger.sh"
                source "{PROJECT_DIR}/lib/ui.sh"
                source "{PROJECT_DIR}/lib/hardware.sh"
                source "{PROJECT_DIR}/lib/ollama.sh"
                source "{PROJECT_DIR}/lib/models.sh"
                source "{PROJECT_DIR}/lib/optimization.sh"
                route_task_to_model "{task_type}" 0
                '''],
                capture_output=True,
                text=True,
                timeout=5,
                cwd=PROJECT_DIR
            )
            if result.returncode == 0 and result.stdout.strip():
                return result.stdout.strip()
        except Exception as e:
            pass
        
        # Fallback to requested model
        return requested_model
    
    def get_optimized_params(self, model, task_type, request_data):
        """Get optimized parameters for model and task"""
        try:
            # Call tune_model_optimized via bash
            tier = os.environ.get('HARDWARE_TIER', 'B')
            result = subprocess.run(
                ['bash', '-c', f'''
                export PROJECT_DIR="{PROJECT_DIR}"
                source "{PROJECT_DIR}/lib/constants.sh"
                source "{PROJECT_DIR}/lib/logger.sh"
                source "{PROJECT_DIR}/lib/ui.sh"
                source "{PROJECT_DIR}/lib/hardware.sh"
                source "{PROJECT_DIR}/lib/ollama.sh"
                source "{PROJECT_DIR}/lib/models.sh"
                source "{PROJECT_DIR}/lib/optimization.sh"
                tune_model_optimized "{model}" "{tier}" "coding" "{task_type}" 0
                '''],
                capture_output=True,
                text=True,
                timeout=5,
                cwd=PROJECT_DIR
            )
            if result.returncode == 0:
                params_json = json.loads(result.stdout)
                return {
                    'num_ctx': params_json.get('context_size', 16384),
                    'num_predict': params_json.get('max_tokens', 2048),
                    'temperature': float(params_json.get('temperature', 0.7))
                }
        except Exception as e:
            pass
        
        # Fallback to basic optimizations
        return {
            'temperature': 0.6 if task_type == 'autocomplete' else 0.7,
            'num_ctx': 8192 if task_type == 'autocomplete' else 16384
        }
    
    def track_performance(self, model, task_type, duration, tokens):
        """Track performance metrics"""
        try:
            subprocess.run(
                ['bash', '-c', f'''
                export PROJECT_DIR="{PROJECT_DIR}"
                source "{PROJECT_DIR}/lib/constants.sh"
                source "{PROJECT_DIR}/lib/logger.sh"
                source "{PROJECT_DIR}/lib/ui.sh"
                source "{PROJECT_DIR}/lib/hardware.sh"
                source "{PROJECT_DIR}/lib/ollama.sh"
                source "{PROJECT_DIR}/lib/models.sh"
                source "{PROJECT_DIR}/lib/optimization.sh"
                track_performance "{model}" "{task_type}" {duration} {tokens} 1
                '''],
                timeout=2,
                cwd=PROJECT_DIR
            )
        except:
            pass
    
    def optimize_prompt(self, prompt, task_type, model):
        """Optimize prompt using bash function for better model responses"""
        if not prompt:
            return prompt
        
        try:
            # Escape prompt for bash (handle quotes and special chars)
            prompt_escaped = prompt.replace("'", "'\"'\"'")
            result = subprocess.run(
                ['bash', '-c', f'''
                export PROJECT_DIR="{PROJECT_DIR}"
                source "{PROJECT_DIR}/lib/constants.sh"
                source "{PROJECT_DIR}/lib/logger.sh"
                source "{PROJECT_DIR}/lib/ui.sh"
                source "{PROJECT_DIR}/lib/hardware.sh"
                source "{PROJECT_DIR}/lib/ollama.sh"
                source "{PROJECT_DIR}/lib/models.sh"
                source "{PROJECT_DIR}/lib/optimization.sh"
                optimize_prompt '{prompt_escaped}' "{task_type}" "{model}"
                '''],
                capture_output=True,
                text=True,
                timeout=3,
                cwd=PROJECT_DIR
            )
            if result.returncode == 0 and result.stdout.strip():
                return result.stdout.strip()
        except Exception as e:
            pass
        
        return prompt
    
    def compress_context_if_needed(self, context, request_data):
        """Compress context if it's too large to prevent overflow errors"""
        if not context:
            return context
        
        # Estimate context size (rough: 4 chars per token)
        context_str = json.dumps(context) if isinstance(context, (list, dict)) else str(context)
        estimated_tokens = len(context_str) // 4
        
        # Get max context from request options
        max_ctx = request_data.get('options', {}).get('num_ctx', 16384)
        
        # Compress if over 80% of max context
        if estimated_tokens > (max_ctx * 0.8):
            try:
                # Escape context string for bash
                context_escaped = context_str.replace("'", "'\"'\"'")
                result = subprocess.run(
                    ['bash', '-c', f'''
                    export PROJECT_DIR="{PROJECT_DIR}"
                    source "{PROJECT_DIR}/lib/constants.sh"
                    source "{PROJECT_DIR}/lib/logger.sh"
                    source "{PROJECT_DIR}/lib/ui.sh"
                    source "{PROJECT_DIR}/lib/hardware.sh"
                    source "{PROJECT_DIR}/lib/ollama.sh"
                    source "{PROJECT_DIR}/lib/models.sh"
                    source "{PROJECT_DIR}/lib/optimization.sh"
                    compress_context '{context_escaped}' {max_ctx} 0.7
                    '''],
                    capture_output=True,
                    text=True,
                    timeout=5,
                    cwd=PROJECT_DIR
                )
                if result.returncode == 0 and result.stdout.strip():
                    compressed = result.stdout.strip()
                    # Try to parse back as JSON if it was JSON
                    try:
                        return json.loads(compressed)
                    except:
                        return compressed
            except Exception as e:
                pass
        
        return context
    
    def execute_ensemble_request(self, ollama_request, task_type, model):
        """Execute request using ensemble of models for higher quality responses"""
        prompt = ollama_request.get('prompt', '')
        
        try:
            # Escape prompt for bash
            prompt_escaped = prompt.replace("'", "'\"'\"'")
            result = subprocess.run(
                ['bash', '-c', f'''
                export PROJECT_DIR="{PROJECT_DIR}"
                source "{PROJECT_DIR}/lib/constants.sh"
                source "{PROJECT_DIR}/lib/logger.sh"
                source "{PROJECT_DIR}/lib/ui.sh"
                source "{PROJECT_DIR}/lib/hardware.sh"
                source "{PROJECT_DIR}/lib/ollama.sh"
                source "{PROJECT_DIR}/lib/models.sh"
                source "{PROJECT_DIR}/lib/optimization.sh"
                execute_ensemble '{prompt_escaped}' "{task_type}" "" "weighted"
                '''],
                capture_output=True,
                text=True,
                timeout=600,  # Longer timeout for ensemble
                cwd=PROJECT_DIR
            )
            if result.returncode == 0 and result.stdout.strip():
                # Format as Ollama response
                response_text = result.stdout.strip()
                response_json = {
                    'model': model,
                    'response': response_text,
                    'done': True
                }
                return json.dumps(response_json).encode('utf-8')
        except Exception as e:
            pass
        
        # Fallback to single model request
        ollama_url = f'{OLLAMA_BASE}{self.path}'
        req = urllib.request.Request(ollama_url, 
                                    data=json.dumps(ollama_request).encode('utf-8'),
                                    headers={'Content-Type': 'application/json'})
        with urllib.request.urlopen(req, timeout=300) as response:
            return response.read()
    
    def track_prompt_performance(self, prompt, task_type, duration, tokens):
        """Track prompt performance for continuous optimization learning"""
        try:
            # Estimate quality score (simple heuristic: faster + more tokens = better)
            quality_score = 5  # Default
            if duration > 0 and tokens > 0:
                tokens_per_sec = tokens / duration
                # Higher tokens/sec = better quality (up to 10)
                quality_score = min(10, max(1, int(tokens_per_sec / 10)))
            
            # Escape prompt for bash
            prompt_escaped = prompt.replace("'", "'\"'\"'")
            subprocess.run(
                ['bash', '-c', f'''
                export PROJECT_DIR="{PROJECT_DIR}"
                source "{PROJECT_DIR}/lib/constants.sh"
                source "{PROJECT_DIR}/lib/logger.sh"
                source "{PROJECT_DIR}/lib/ui.sh"
                source "{PROJECT_DIR}/lib/hardware.sh"
                source "{PROJECT_DIR}/lib/ollama.sh"
                source "{PROJECT_DIR}/lib/models.sh"
                source "{PROJECT_DIR}/lib/optimization.sh"
                track_prompt_performance '{prompt_escaped}' "" "{task_type}" 1 {duration} {quality_score}
                '''],
                timeout=2,
                cwd=PROJECT_DIR
            )
        except:
            pass
    
    def log_message(self, format, *args):
        """Suppress default logging"""
        pass

if __name__ == '__main__':
    # Auto-start other optimization services (unless disabled)
    ensure_optimization_services_running()
    
    PORT = int(os.environ.get('PROXY_PORT', '11435'))
    
    with socketserver.TCPServer(("", PORT), OptimizationProxyHandler) as httpd:
        print(f"Ollama Optimization Proxy running on port {PORT}")
        print(f"Forwarding to Ollama on port {OLLAMA_PORT}")
        print("\nAdvanced Optimizations:")
        print(f"  ✓ Prompt Optimization: {'ENABLED' if ENABLE_PROMPT_OPTIMIZATION else 'DISABLED'}")
        print(f"  ✓ Context Compression: {'ENABLED' if ENABLE_CONTEXT_COMPRESSION else 'DISABLED'}")
        print(f"  ✓ Model Ensemble: {'ENABLED' if ENABLE_ENSEMBLE else 'DISABLED'}")
        print("\nUpdate Continue.dev config: apiBase: http://localhost:11435")
        print("Press Ctrl+C to stop")
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nShutting down proxy...")
