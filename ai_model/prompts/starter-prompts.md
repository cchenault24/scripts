# Starter Prompts for React + TypeScript + Redux-Saga Stack

This document contains optimized prompt templates for your local AI coding assistant. These prompts are designed to work with Continue.dev and are tailored for your specific tech stack.

## Stack Context

- **React** with TypeScript (strict typing, no `any`)
- **Redux** + **Redux-Saga** (side effects in sagas, typed selectors)
- **Material UI (MUI)** (theme-first styling, sx with tokens)
- **AG Grid** (typed column defs, memoized renderers)
- **OpenLayers** (isolated map state, lifecycle management)

## Safe Refactoring Prompts

### Request Files First
```
Before making changes, please:
1. Show me all files that would be affected by this refactor
2. Explain the risks and benefits
3. Propose minimal, incremental changes
4. Preserve all TypeScript types and architecture patterns
```

### Component Refactoring
```
Refactor this React component to:
- Use strict TypeScript (no 'any', proper generics)
- Extract side effects to a Redux-Saga if needed
- Use MUI theme tokens via sx prop (no inline styles)
- Add proper error boundaries and loading states
- Maintain existing functionality exactly

Show me the diff first before applying.
```

### Redux-Saga Refactoring
```
Refactor this Redux-Saga to:
- Use takeLatest instead of takeEvery (or vice versa if appropriate)
- Add proper cancellation handling
- Implement typed selectors
- Add comprehensive error handling
- Follow saga best practices

Explain the changes and show the diff.
```

### Type Safety Improvements
```
Review this code and:
- Identify any 'any' types
- Suggest proper TypeScript types (generics, discriminated unions)
- Ensure type safety throughout
- Add missing type annotations

Show me the improvements with explanations.
```

## Code Review Prompts

### General Code Review
```
Review this code for:
- Correctness and edge cases
- TypeScript type safety (no 'any')
- React best practices
- Performance issues
- Accessibility concerns

Provide specific, actionable feedback with code examples.
```

### Redux-Saga Review
```
Review this Redux-Saga implementation:
- Lifecycle management (cancellation, cleanup)
- Error handling patterns
- Selector usage (typed, memoized)
- Side effect isolation
- Testability

Focus on saga-specific patterns and potential issues.
```

### MUI Component Review
```
Review this MUI component:
- Theme usage (sx prop with tokens, no inline styles)
- Accessibility (ARIA labels, keyboard navigation)
- Responsive design
- Performance (memoization, re-render optimization)

Provide MUI-specific recommendations.
```

### AG Grid Review
```
Review this AG Grid implementation:
- Column definition types
- Renderer memoization
- Performance optimizations
- Cell editor patterns
- Event handling

Focus on AG Grid best practices and performance.
```

### OpenLayers Review
```
Review this OpenLayers map component:
- Lifecycle management (cleanup on unmount)
- Event listener safety (proper removal)
- Map state isolation
- Memory leak prevention
- Performance considerations

Check for proper cleanup and lifecycle management.
```

## Component Generation Prompts

### React Component with Redux
```
Create a React component with TypeScript that:
- Uses Redux state via typed selectors
- Dispatches actions (no direct API calls in component)
- Uses MUI components with theme-first styling (sx prop)
- Includes proper loading and error states
- Has comprehensive TypeScript types (no 'any')
- Follows React best practices (hooks, memoization)

Include:
- Component file
- Redux actions/types (if new)
- Saga for side effects (if needed)
- Selector (typed)
```

### Redux-Saga Implementation
```
Create a Redux-Saga that:
- Handles [specific action]
- Uses takeLatest/takeEvery appropriately
- Implements proper cancellation
- Has comprehensive error handling
- Uses typed selectors
- Follows saga patterns

Include:
- Saga implementation
- Action types
- Error handling
- Tests (if applicable)
```

### MUI Themed Component
```
Create a MUI component that:
- Uses theme tokens via sx prop
- Is fully accessible (ARIA, keyboard nav)
- Is responsive
- Uses MUI components (not custom styled)
- Has proper TypeScript types

Show me the component with theme integration.
```

### AG Grid Table
```
Create an AG Grid table with:
- Typed column definitions
- Memoized cell renderers
- Proper TypeScript types
- Row selection (if needed)
- Sorting/filtering (if needed)
- Performance optimizations

Include column defs, renderers, and types.
```

## Architecture Questions

### Multi-File Context
```
Analyze these files together:
[list files]

Explain:
- How they interact
- Potential issues
- Refactoring opportunities
- Architecture improvements

Consider the full context across all files.
```

### Semantic Code Search
```
Find all places in the codebase where:
- [specific pattern or functionality]
- [specific Redux action is used]
- [specific MUI component is used]
- [specific TypeScript type is used]

Show me the locations and explain the patterns.
```

### State Management Analysis
```
Analyze the Redux state structure:
- Is state normalized appropriately?
- Are selectors typed and memoized?
- Are side effects properly isolated in sagas?
- Are there opportunities for optimization?

Provide recommendations with examples.
```

## Documentation Prompts

### Component Documentation
```
Generate documentation for this React component:
- Purpose and usage
- Props (with TypeScript types)
- Examples
- Related Redux actions/sagas
- Dependencies

Format as JSDoc comments.
```

### Saga Documentation
```
Document this Redux-Saga:
- What it does
- What actions it handles
- Side effects it manages
- Error handling
- Dependencies

Include usage examples and flow diagrams if helpful.
```

### API Integration Documentation
```
Document this API integration:
- Endpoints used
- Request/response types
- Error handling
- Redux integration
- Saga implementation

Include TypeScript types and examples.
```

## Troubleshooting Prompts

### Debug TypeScript Errors
```
Help me fix these TypeScript errors:
[error messages]

Explain:
- What's causing the errors
- How to fix them properly
- How to prevent similar issues

Maintain type safety throughout.
```

### Performance Issues
```
Analyze this code for performance issues:
- Unnecessary re-renders
- Missing memoization
- Inefficient selectors
- Memory leaks
- Bundle size concerns

Provide specific optimizations with code examples.
```

### Redux-Saga Debugging
```
Help me debug this Redux-Saga issue:
[describe the problem]

Check for:
- Cancellation issues
- Error handling gaps
- Selector problems
- Side effect isolation

Provide solutions with explanations.
```

## Best Practices Reminders

When using these prompts, remember:

1. **Always request files first** for multi-file changes
2. **Propose minimal diffs** - incremental changes are safer
3. **Explain risks** - understand what could break
4. **Preserve typing** - maintain TypeScript strictness
5. **Follow architecture** - keep side effects in sagas
6. **Use theme tokens** - MUI sx prop, not inline styles
7. **Memoize appropriately** - AG Grid renderers, React components
8. **Clean up properly** - OpenLayers lifecycle, event listeners

## Customization

Feel free to customize these prompts for your specific needs. The key is to:
- Be specific about your stack
- Request context before changes
- Ask for explanations
- Prefer incremental over broad changes
