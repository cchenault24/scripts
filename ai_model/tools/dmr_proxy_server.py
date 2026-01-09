#!/usr/bin/env python3
"""
Docker Model Runner (DMR) Optimization Proxy Server
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

DMR_PORT = int(os.environ.get('DMR_PORT', '12434'))
PROJECT_DIR = os.environ.get('PROJECT_DIR', '/Users/chenaultfamily/Documents/coding/scripts/ai_model')
DMR_BASE = f'http://localhost:{DMR_PORT}/engines/v1'

# Advanced optimization flags (can be set via environment variables)
ENABLE_PROMPT_OPTIMIZATION = os.environ.get('ENABLE_PROMPT_OPTIMIZATION', '1') == '1'
ENABLE_CONTEXT_COMPRESSION = os.environ.get('ENABLE_CONTEXT_COMPRESSION', '1') == '1'
ENABLE_ENSEMBLE = os.environ.get('ENABLE_ENSEMBLE', '0') == '1'  # Off by default (slower but better quality)

class OptimizationProxyHandler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        """Handle POST requests (OpenAI-compatible API calls)"""
        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length)
        
        try:
            request_data = json.loads(body.decode('utf-8'))
            model = request_data.get('model', '')
            messages = request_data.get('messages', [])
            
            # Extract prompt from messages (OpenAI format)
            prompt = self.extract_prompt_from_messages(messages)
            
            # Determine task type from prompt/messages
            task_type = self.detect_task_type(prompt, request_data)
            
            # Optimize prompt for better results
            if ENABLE_PROMPT_OPTIMIZATION:
                prompt = self.optimize_prompt(prompt, task_type, model)
                # Update messages with optimized prompt
                if messages and len(messages) > 0:
                    messages[-1]['content'] = prompt
            
            # Compress context if it's too large
            if ENABLE_CONTEXT_COMPRESSION and messages:
                messages = self.compress_messages_if_needed(messages, request_data)
                request_data['messages'] = messages
            
            # Apply optimizations via bash functions
            optimized_model = self.route_to_optimal_model(model, task_type)
            optimized_params = self.get_optimized_params(optimized_model, task_type, request_data)
            
            # Use ensemble if enabled (for complex tasks - slower but higher quality)
            use_ensemble = ENABLE_ENSEMBLE and task_type in ['refactoring', 'complex', 'analysis']
            
            # Forward to DMR with optimizations (OpenAI-compatible format)
            dmr_request = request_data.copy()
            dmr_request['model'] = optimized_model
            dmr_request['messages'] = messages
            # Update parameters
            if 'max_tokens' not in dmr_request or optimized_params.get('max_tokens'):
                dmr_request['max_tokens'] = optimized_params.get('max_tokens', 2048)
            if 'temperature' not in dmr_request or optimized_params.get('temperature') is not None:
                dmr_request['temperature'] = optimized_params.get('temperature', 0.7)
            
            # Track performance start
            start_time = time.time()
            
            # Execute with ensemble if enabled, otherwise normal request
            if use_ensemble:
                response_data = self.execute_ensemble_request(dmr_request, task_type, optimized_model)
            else:
                # Forward to DMR (OpenAI-compatible endpoint)
                dmr_url = f'{DMR_BASE}/chat/completions'
                req = urllib.request.Request(dmr_url, 
                                            data=json.dumps(dmr_request).encode('utf-8'),
                                            headers={'Content-Type': 'application/json'})
                
                try:
                    with urllib.request.urlopen(req, timeout=300) as response:
                        response_data = response.read()
                except Exception as e:
                    self.send_error(500, f"DMR request failed: {str(e)}")
                    return
            
            duration = time.time() - start_time
            
            # Extract token count from response
            try:
                resp_json = json.loads(response_data.decode('utf-8'))
                # OpenAI format: choices[0].message.content
                content = resp_json.get('choices', [{}])[0].get('message', {}).get('content', '')
                tokens = len(content.split()) if content else 0
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
        """Forward GET requests directly to DMR"""
        dmr_url = f'{DMR_BASE}{self.path}'
        try:
            with urllib.request.urlopen(dmr_url, timeout=10) as response:
                self.send_response(response.status)
                for header, value in response.headers.items():
                    if header.lower() not in ['connection', 'transfer-encoding']:
                        self.send_header(header, value)
                self.end_headers()
                self.wfile.write(response.read())
        except Exception as e:
            self.send_error(500, f"DMR request failed: {str(e)}")
    
    def extract_prompt_from_messages(self, messages):
        """Extract prompt text from OpenAI messages format"""
        if not messages:
            return ""
        # Get the last user message
        for msg in reversed(messages):
            if msg.get('role') == 'user':
                return msg.get('content', '')
        # Fallback: concatenate all content
        return ' '.join([msg.get('content', '') for msg in messages if msg.get('content')])
    
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
                source "{PROJECT_DIR}/lib/dmr.sh"
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
                source "{PROJECT_DIR}/lib/dmr.sh"
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
                    'max_tokens': params_json.get('max_tokens', 2048),
                    'temperature': float(params_json.get('temperature', 0.7))
                }
        except Exception as e:
            pass
        
        # Fallback to basic optimizations
        return {
            'temperature': 0.6 if task_type == 'autocomplete' else 0.7,
            'max_tokens': 1024 if task_type == 'autocomplete' else 2048
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
                source "{PROJECT_DIR}/lib/dmr.sh"
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
                source "{PROJECT_DIR}/lib/dmr.sh"
                source "{PROJECT_DIR}/lib/models.sh"
                source "{PROJECT_DIR}/lib/optimization.sh"
                optimize_prompt '{prompt_escaped}' "{task_type}" "{model}"
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
        
        return prompt
    
    def compress_messages_if_needed(self, messages, request_data):
        """Compress messages if context is too large"""
        # Estimate total context size
        total_chars = sum(len(msg.get('content', '')) for msg in messages)
        max_ctx = request_data.get('max_tokens', 2048) * 4  # Rough estimate: 4 chars per token
        
        if total_chars > max_ctx * 0.8:  # Compress if over 80% of max
            try:
                # Compress the last user message (usually the longest)
                if messages and messages[-1].get('role') == 'user':
                    content = messages[-1].get('content', '')
                    content_escaped = content.replace("'", "'\"'\"'")
                    result = subprocess.run(
                        ['bash', '-c', f'''
                        export PROJECT_DIR="{PROJECT_DIR}"
                        source "{PROJECT_DIR}/lib/constants.sh"
                        source "{PROJECT_DIR}/lib/logger.sh"
                        source "{PROJECT_DIR}/lib/ui.sh"
                        source "{PROJECT_DIR}/lib/hardware.sh"
                        source "{PROJECT_DIR}/lib/dmr.sh"
                        source "{PROJECT_DIR}/lib/models.sh"
                        source "{PROJECT_DIR}/lib/optimization.sh"
                        compress_context '{content_escaped}' {max_ctx} 0.7
                        '''],
                        capture_output=True,
                        text=True,
                        timeout=5,
                        cwd=PROJECT_DIR
                    )
                    if result.returncode == 0 and result.stdout.strip():
                        messages[-1]['content'] = result.stdout.strip()
            except Exception as e:
                pass
        
        return messages
    
    def execute_ensemble_request(self, dmr_request, task_type, model):
        """Execute request using ensemble of models for higher quality responses"""
        messages = dmr_request.get('messages', [])
        prompt = self.extract_prompt_from_messages(messages)
        
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
                source "{PROJECT_DIR}/lib/dmr.sh"
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
                # Format as OpenAI-compatible response
                response_text = result.stdout.strip()
                response_json = {
                    'id': 'chatcmpl-' + str(int(time.time())),
                    'object': 'chat.completion',
                    'created': int(time.time()),
                    'model': model,
                    'choices': [{
                        'index': 0,
                        'message': {
                            'role': 'assistant',
                            'content': response_text
                        },
                        'finish_reason': 'stop'
                    }],
                    'usage': {
                        'prompt_tokens': len(prompt.split()),
                        'completion_tokens': len(response_text.split()),
                        'total_tokens': len(prompt.split()) + len(response_text.split())
                    }
                }
                return json.dumps(response_json).encode('utf-8')
        except Exception as e:
            pass
        
        # Fallback to single model request
        dmr_url = f'{DMR_BASE}/chat/completions'
        req = urllib.request.Request(dmr_url, 
                                    data=json.dumps(dmr_request).encode('utf-8'),
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
                source "{PROJECT_DIR}/lib/dmr.sh"
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
    PORT = int(os.environ.get('PROXY_PORT', '12435'))
    
    with socketserver.TCPServer(("", PORT), OptimizationProxyHandler) as httpd:
        print(f"DMR Optimization Proxy running on port {PORT}")
        print(f"Forwarding to DMR on port {DMR_PORT}")
        print("\nAdvanced Optimizations:")
        print(f"  ✓ Prompt Optimization: {'ENABLED' if ENABLE_PROMPT_OPTIMIZATION else 'DISABLED'}")
        print(f"  ✓ Context Compression: {'ENABLED' if ENABLE_CONTEXT_COMPRESSION else 'DISABLED'}")
        print(f"  ✓ Model Ensemble: {'ENABLED' if ENABLE_ENSEMBLE else 'DISABLED'}")
        print(f"\nUpdate Continue.dev config: apiBase: http://localhost:{PORT}/engines/v1")
        print("Press Ctrl+C to stop")
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nShutting down proxy...")
