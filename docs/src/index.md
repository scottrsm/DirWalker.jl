# DirWalker.jl Documentation

```@meta
CurrentModule = DirWalker
```

# Overview
This module provides a struct, `DirItr`, that implements the Iterator Protocol
for a directory tree, allowing one to iterate in a linear way over the tree.
The DirItr struct has fields that control this iteration in terms of pruning,
sorting, and ordering.

## Types

```@docs
DirItr
```

## Outer Constructor

```@docs
DirItr(path::String; by_depth::Bool=true, dprune::AbstractVector{<:AbstractString}=[raw"^\.git$"],
		fprune::AbstractVector{<:AbstractString}=String[], ordered::Bool=true, order_dir::Symbol=:asc, order_by=lowercase,
		follow_symlinks::Bool=false, onerror=nothing)
```

## Index

```@index
```
