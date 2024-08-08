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
DirItr(p::String; by_depth::Bool=true, dprune::AbstractVector{String}=[raw"^\.git$", raw"\.github$"],
		fprune::AbstractVector{String}=[raw"^$"], ordered::Bool=false, order_by::Function=lowercase) 
```

## Index

```@index
```
