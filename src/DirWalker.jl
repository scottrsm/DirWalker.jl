module DirWalker

export DirItr


#= DESCRIPTION: Creation of a structure that can be used as a directory tree iterator.
              The resulting object is light weight but can be used to walk through 
              a directory tree. This is done by implementing the Base.iterate protocol
              for this struct. We also use the attributes of the struct to modify
              how the walk should occur.

 Example use:
      d = DirItr(joinpath(homedir(), "proj"))
      for file in d
         println("file = $file")
      end
=#

"""
    DirItr

The structure is a light-weight handle used to linearize a directory tree starting
at the path: `path`. This linearization is done by implementing the
Base.iterate protocol for this struct. Iterating yields the path of every file
in the tree (each path is `path` joined with the file's relative location).
The other fields determine how the linearization is done.

# Fields
- `path     :: String`   -- The path to the root directory.
- `by_depth :: Bool`     -- If `true`, traverse depth-first; otherwise, breadth-first.
- `dprune   :: Regex`    -- A regular expression used to prune (skip) directories.
- `fprune   :: Regex`    -- A regular expression used to prune (skip) files.
- `ordered  :: Bool`     -- Is the output of directories and files ordered.
- `order_dir:: Symbol`   -- Order direction. One of: `:asc` (ascending), `:desc` (descending).
- `order_by :: F`        -- If `ordered`, function that determines the ordering.
                            This function is used with the `sort` function's `by` argument.
- `follow_symlinks :: Bool` -- If `true`, descend into symbolic links to directories
                            (each real directory is visited at most once, so cycles are safe).
                            If `false` (the default), a symbolic link is yielded as a file and not followed.
- `onerror  :: Union{Nothing, Function}` -- If a directory cannot be read, this function is
                            called with the `IOError` and the directory is skipped.
                            If `nothing` (the default), the error is thrown.
"""
struct DirItr{F, E}
	path::String        # Path to the root directory.
	by_depth ::Bool     # How to do the search of the directory tree. 
	                    # If `true`, by depth; otherwise, breadth-first search.
	dprune   ::Regex    # A Regular Expression, used to avoid certain directories.
	fprune   ::Regex    # A Regular Expression, used to avoid certain files.
	ordered  ::Bool     # If `true`, order the files and directories.
	order_dir::Symbol   # Order direction. One of: :asc (ascending), :desc (descending) .
	order_by ::F        # When sorting (`ordered=true`), use this function with the `sort` function's `by` argument.
	follow_symlinks::Bool # Descend into symbolic links to directories?
	onerror  ::E        # `nothing`, or a function called with the `IOError` of an unreadable directory.
end

# A pattern that never matches a directory entry name (entry names are never empty).
const NO_MATCH = r"^$"

# Join a vector of regular expression strings into one regular expression;
# an empty vector matches nothing.
_join_regex(pats::AbstractVector{<:AbstractString}) = isempty(pats) ? NO_MATCH : Regex(join(pats, "|"))

"""
	DirItr(path::String; <key-word-args>)

Outer constructor for DirItr.

# Arguments
- `path :: String`  -- The path to the root directory. Must be a readable directory.

# Keyword Arguments
- `by_depth::Bool=true`                             -- How to traverse the tree: depth-first, or breadth-first.
- `dprune::AbstractVector{String}=[raw"^\\.git\$"]` -- A vector of regular expression strings. A directory whose
                                                       **name** (not its full path) matches any of them is skipped, with
                                                       everything below it. The default by-passes any git tree.
                                                       An empty vector prunes nothing.
- `fprune::AbstractVector{String}=String[]`         -- A vector of regular expression strings. A file whose
                                                       **name** matches any of them is skipped. The default prunes nothing.
- `ordered::Bool=true`                              -- If `true`, order the resulting files and directories;
                                                       otherwise, they are yielded in the order the file system lists them.
- `order_dir::Symbol=:asc`                          -- Order direction. One of: :asc (ascending), :desc (descending) .
- `order_by=lowercase`                              -- If `ordered` is `true`, order the resulting files and directories with
                                                       the sort using `order_by` as the sorting key: sort(...; by=`order_by`[,...])
- `follow_symlinks::Bool=false`                     -- If `true`, descend into symbolic links to directories (each real
                                                       directory is visited at most once). If `false`, a symbolic link is
                                                       yielded as a file and not followed.
- `onerror=nothing`                                 -- If a directory cannot be read: when `nothing`, the `IOError` is thrown;
                                                       otherwise `onerror` is called with the error and the directory is skipped.
# Return
`::DirItr`
"""
function DirItr(path::String; by_depth::Bool=true, dprune::AbstractVector{<:AbstractString}=[raw"^\.git$"],
		fprune::AbstractVector{<:AbstractString}=String[], ordered::Bool=true, order_dir::Symbol=:asc, order_by=lowercase,
		follow_symlinks::Bool=false, onerror=nothing) 
	in(order_dir, (:asc, :desc)) || throw(ArgumentError("Parameter `order_dir` should be one of: :asc, :desc; got: $order_dir"))
	isdir(path) || throw(ArgumentError("DirItr: `path` is not a readable directory: $path"))
	return DirItr(path, by_depth, _join_regex(dprune), _join_regex(fprune), ordered, order_dir, order_by, follow_symlinks, onerror) 
end


# Compact show method for DirItr iterator (inside containers, error messages, ...).
Base.show(io::IO, di::DirItr) = print(io, "DirItr(", repr(di.path), ")")

# Verbose show method for DirItr iterator (REPL).
function Base.show(io::IO, ::MIME"text/plain", di::DirItr) 
	print(io, 
		  """DirItr:
		  \tpath            = $(di.path)
		  \tby_depth        = $(di.by_depth)
		  \tdprune          = $(di.dprune)
		  \tfprune          = $(di.fprune)
		  \tordered         = $(di.ordered)
		  \torder_dir       = $(di.order_dir)
		  \torder_by        = $(di.order_by)
		  \tfollow_symlinks = $(di.follow_symlinks)
		  \tonerror         = $(di.onerror)"""  )
end

# Size and element type of DirItr iterator.
Base.IteratorSize(::Type{<:DirItr}) = Base.SizeUnknown()
Base.eltype(::Type{<:DirItr}) = String

# The iteration state: files still to yield, directories still to visit,
# and (when following symbolic links) the real paths of directories already visited.
struct DirState
	files  ::Vector{String}
	dirs   ::Vector{String}
	visited::Set{String}
end

# Is this entry a directory we should descend into?
function _is_walkable_dir(di::DirItr, p::String)
	if islink(p)
		return di.follow_symlinks && isdir(p)
	end
	return isdir(p)
end

#= Read the directory `dir` and add its files and sub-directories to the state.
   The details of this are altered by the attributes in `di`.
   Returns `false` if the directory could not be read (and `di.onerror` handled it).
=#
function _gather_files!(di::DirItr, dir::String, st::DirState)
	# When following symbolic links, never visit the same real directory twice.
	if di.follow_symlinks
		rp = realpath(dir)
		rp in st.visited && return false
		push!(st.visited, rp)
	end

	# Get the contents of the directory, `dir` -- sorted only if the output should be ordered.
	contents = try
		readdir(dir; sort=di.ordered)
	catch e
		(di.onerror !== nothing && e isa Base.IOError) || rethrow()
		di.onerror(e)
		return false
	end

	# Group the contents into ndirs and nfiles -- one `stat` per entry.
	ndirs  = String[]
	nfiles = String[]
	for x in contents
		if _is_walkable_dir(di, joinpath(dir, x))
			match(di.dprune, x) === nothing && push!(ndirs, x)
		else
			match(di.fprune, x) === nothing && push!(nfiles, x)
		end
	end

	# Order files and directories.
	# (Sorted in the opposite way as the files will eventually be popped off a list.)
	if di.ordered
		sort!(nfiles, by=di.order_by, rev=(di.order_dir === :asc))
		sort!(ndirs,  by=di.order_by, rev=(di.order_dir === :asc))
	else
		reverse!(nfiles)
		reverse!(ndirs)
	end

	# Prepend the directory path to the contents -- so they have full paths.
	ndirs  = [joinpath(dir, d) for d in ndirs] 
	nfiles = [joinpath(dir, f) for f in nfiles] 

	# Merge the new files and directories with the current ones.
	if di.by_depth 
		append!(st.files, nfiles)
		append!(st.dirs, ndirs)
	else
		prepend!(st.files, nfiles)
		prepend!(st.dirs, ndirs)
	end
	return true
end

#= Gets the next file and "state".
   Returns `nothing` if there is no next file; or,
   the tuple: (file, state).
   This is the form that Base.iterate for `DirItr` expects.
=#
function _get_next_state(di::DirItr, st::DirState)
	while true
		if !isempty(st.files)
			return (pop!(st.files), st)
		end
		# No files waiting: read the next directory (if any) and try again.
		isempty(st.dirs) && return nothing
		_gather_files!(di, pop!(st.dirs), st)
	end
end

#= This function gets the next file to return.
   This function is called the first time in the iteration process.
   It reads the top level directory (specified by di.path) creating
   a vector of files and directories. It then calls _get_next_state
   which does the work of producing the next file and updating the state.
   Returns `nothing` if the tree has no files; otherwise a two-tuple consisting
   of the next-file and the "state": ( next_file::String, state::DirState )
=#
function Base.iterate(di::DirItr)
	# First check if the path exists.
	isdir(di.path) || throw(ArgumentError("DirItr: `path` is not a readable directory: $(di.path)"))

	st = DirState(String[], String[], Set{String}())
	_gather_files!(di, di.path, st)

	return _get_next_state(di, st)
end

#= This function gets called on subsequent iterations...
   Returns a two-tuple consisting of the next-file and the "state":
   ( next_file::String, state::DirState )
=#
Base.iterate(di::DirItr, st::DirState) = _get_next_state(di, st)

end # module DirWalker
