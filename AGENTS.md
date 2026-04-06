# OpenCode Agent Instructions

## Tool Usage Guidelines

When using tools, follow these exact parameter names:

### File Operations

**Read files:**
```
{
  "name": "read",
  "arguments": {
    "path": "path/to/file.txt"
  }
}
```

**Edit files:**
```
{
  "name": "edit",
  "arguments": {
    "path": "path/to/file.txt",
    "instructions": "what to change"
  }
}
```

**Create files:**
```
{
  "name": "write",
  "arguments": {
    "path": "path/to/file.txt",
    "content": "file contents"
  }
}
```

### Shell Commands

**Run bash commands:**
```
{
  "name": "bash",
  "arguments": {
    "command": "ls -la"
  }
}
```

### Web Access

**Fetch web pages:**
```
{
  "name": "webfetch",
  "arguments": {
    "url": "https://example.com",
    "query": "what information to extract"
  }
}
```

## Important Rules

1. Always use exact parameter names shown above
2. For file paths, use forward slashes (/)
3. For bash commands, test with simple commands first
4. Check tool results before proceeding
5. If a tool fails, read the error and try again with corrections
