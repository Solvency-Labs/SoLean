import Lake
open Lake DSL

package solean where
  -- Keep the first prototype dependency-free. Add dependencies only when they
  -- remove real proof or engineering friction.

@[default_target]
lean_lib SoLean where
