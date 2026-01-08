# Stack-Specific Best Practices

## TypeScript

- **Strict typing**: No `any`, use generics and discriminated unions
- **Type safety**: Enable all strict checks in `tsconfig.json`
- **Typed selectors**: Use typed Redux selectors

## Redux + Redux-Saga

- **Side effects in sagas**: Never in components
- **Typed selectors**: Use TypeScript for all selectors
- **Saga patterns**: Use takeLatest/takeEvery appropriately
- **Cancellation**: Always handle saga cancellation
- **Error handling**: Comprehensive error handling in sagas

## Material UI (MUI)

- **Theme-first**: Use sx prop with theme tokens
- **No inline styles**: Avoid ad-hoc inline styles
- **Accessibility**: Proper ARIA labels, keyboard navigation
- **Responsive**: Use MUI breakpoints

## AG Grid

- **Typed column defs**: Use TypeScript for column definitions
- **Memoized renderers**: Memoize cell renderers for performance
- **Performance**: Use virtualization, row grouping appropriately

## OpenLayers

- **Lifecycle management**: Clean up on component unmount
- **Event listeners**: Properly remove all event listeners
- **Map state**: Isolate map state, don't mix with component state
- **Memory leaks**: Check for proper cleanup
