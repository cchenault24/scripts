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

class OptimizationProxyHandler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        """Handle POST requests (Ollama API calls)"""
        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length)
        
        try:
            request_data = json.loads(body.decode('utf-8'))
            model = request_data.get('model', '')
            prompt = request_data.get('prompt', '')
            
            # Determine task type from prompt/context
            task_type = self.detect_task_type(prompt, request_data)
            
            # Apply optimizations via bash functions
            optimized_model = self.route_to_optimal_model(model, task_type)
            optimized_params = self.get_optimized_params(optimized_model, task_type, request_data)
            
            # Forward to Ollama with optimizations
            ollama_request = request_data.copy()
            ollama_request['model'] = optimized_model
            if 'options' not in ollama_request:
                ollama_request['options'] = {}
            ollama_request['options'].update(optimized_params)
            
            # Track performance start
            start_time = time.time()
            
            # Forward to Ollama
            ollama_url = f'{OLLAMA_BASE}{self.path}'
            req = urllib.request.Request(ollama_url, 
                                        data=json.dumps(ollama_request).encode('utf-8'),
                                        headers={'Content-Type': 'application/json'})
            
            try:
                with urllib.request.urlopen(req, timeout=300) as response:
                    response_data = response.read()
                    duration = time.time() - start_time
                    
                    # Extract token count from response
                    try:
                        resp_json = json.loads(response_data.decode('utf-8'))
                        tokens = len(resp_json.get('response', '').split()) if 'response' in resp_json else 0
                    except:
                        tokens = 0
                    
                    # Track performance
                    self.track_performance(optimized_model, task_type, duration, tokens)
                    
                    # Return response
                    self.send_response(200)
                    self.send_header('Content-Type', 'application/json')
                    self.end_headers()
                    self.wfile.write(response_data)
            except Exception as e:
                self.send_error(500, f"Ollama request failed: {str(e)}")
                
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
    
    def log_message(self, format, *args):
        """Suppress default logging"""
        pass

if __name__ == '__main__':
    PORT = int(os.environ.get('PROXY_PORT', '11435'))
    
    with socketserver.TCPServer(("", PORT), OptimizationProxyHandler) as httpd:
        print(f"Ollama Optimization Proxy running on port {PORT}")
        print(f"Forwarding to Ollama on port {OLLAMA_PORT}")
        print("Update Continue.dev config: apiBase: http://localhost:11435")
        print("Press Ctrl+C to stop")
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nShutting down proxy...")
