module DirWalker

export DirItr


#= DESCRIPTION: Creation of a structure that can be used as a directory tree iterator.
              The resulting object is light weight but can be used to walk through 
              a directory tree. This is done by implementing the Base.iterate protocol
              for this struct. We also use the attributes of the struct to modify
              how the walk should occur.

 Example use:
      d = DirItr("/home/rsm/proj/github/Cluster.jl")
      for file in d
         println("file = $file")
      end
=#

"""
 The structure is a light-weight handle used to linearize a directory tree starting
 at the absolute path: `path`. This linearization is done by implementing the
 Base.iterate protocol for this struct.
 The other fields determine how the linearization is done.

# Fields
- `path     :: String`   --  The absolute path to the root directory.
- `by_depth :: Bool`     -- If `true`, traverse depth-first; otherwise, breadth-first.
- `dprune   :: Regex`    -- A regular expression used to prune (skip) directories.
- `fprune   :: Regex`    -- A regular expression used to prune (skip) files.
- `ordered  :: Bool`     -- Is the output of directories and files ordered.
- `order_dir:: Symbol`   -- Order direction. One of: `:asc` (ascending), `:desc` (descending).
- `order_by :: Function` -- If `ordered`, function that determines the ordering.
                            This function is used with the `sort` function's `by` argument.
"""
struct DirItr
	path::String        # Full path to the root directory.
	by_depth ::Bool     # How to do the search of the directory tree. 
	                    # If `true`, by depth; otherwise, breadth-first search.
	dprune   ::Regex    # A Regular Expression, used to avoid certain directories.
	fprune   ::Regex    # A Regular Expression, used to avoid certain files.
	ordered  ::Bool     # If `true`, order the files and directories.
	order_dir::Symbol   # Order direction. One of: :asc (ascending), :desc (descending) .
	order_by ::Function # When sorting (`ordered=true`), use this function with the `sort` function's `by` argument.
end

"""
	DirItr(p::String; <key-word-args>)

Outer constructor for DirItr.

# Arguments
- `path :: String`  -- The full path to the root directory.

# Keyword Arguments
- `by_depth::Bool=true`                              -- How to traverse the tree: depth-first, or breadth-first.
- `dprune=::AbstractVector{String}=[raw"^\\.git\$"]` -- A D vector of regular expression strings. This iterator by-passes any git tree.
- `fprune=::AbstractVector{String}=[raw"^\$"]`       -- A F vector of regular expression strings. This iterator does not filter any files.
- `ordered::Bool=true`                               -- If `true`, order the resulting files and directories.
- `order_dir::Symbol=:asc`                           -- Order direction. One of: :asc (ascending), :desc (descending) .
- `order_by::Function=lowercase`                     -- If `ordered` is `true`, order the resulting files and directories with
                                                        the sort using `order_by` as the sorting keyi: sort(...; by=`order_by`[,...])
# Return
`::DirItr`
"""
function DirItr(p::String; by_depth::Bool=true, dprune::AbstractVector{String}=[raw"^\.git$"],
		fprune::AbstractVector{String}=[raw"^$"], ordered::Bool=true, order_dir::Symbol=:asc, order_by::Function=lowercase) 
	in(order_dir, [:asc, :desc]) || throw(ArgumentError("Parameter `order_dir` should be one of: :asc, :desc; got: $order_dir"))
	return DirItr(p, by_depth, Regex(join(dprune, "|")), Regex(join(fprune, "|")), ordered, order_dir, order_by) 
end


# Show method for DirItr iterator.
function Base.show(io::IO, di::DirItr) 
	print(io, 
		  """DirItr:
		  \tpath     = $(di.path)
		  \tby_depth = $(di.by_depth)
		  \tdprune   = $(di.dprune)
		  \tfprune   = $(di.fprune)
		  \tordered  = $(di.ordered)
		  \torder_dir= $(di.order_dir)
		  \torder_by = $(di.order_by)
		  """                         )
end

# Size and element type of DirItr iterator.
Base.IteratorSize(::Type{DirItr}) = Base.SizeUnknown()
Base.eltype(::Type{DirItr}) = String

#= This function determines how the files and directories will
   be gathered up and given to the function get_next_state__.
   The details of this are altered by the attributes in `d`.
=#
function _gather_files(di::DirItr                    , 
						dir::String                   , 
						files::Vector{String}=String[], 
						dirs::Vector{String}=String[]  )
	# Get the contents of the directory, `dir`.
	contents = readdir(dir)

	# Group the contents into ndirs and nfiles.
	ndirs = filter(x -> isdir(joinpath(dir, x)), contents)
	if di.dprune.pattern != "^\$"
		ndirs = filter(x -> match(di.dprune, x) === nothing, ndirs )
	end

	nfiles = filter(x -> !isdir(joinpath(dir, x)), contents)
	if di.fprune.pattern != "^\$"
		nfiles = filter(x -> match(di.fprune, x) === nothing, nfiles)
	end

	# Only return non-trivial values if there is something in the directory.
	if (length(ndirs) + length(nfiles)) == 0
		return nothing
	end

	# Order files and directories.
	# (Sorted in the opposite way as the files will eventually be popped of a list.)
	if di.ordered
		sort!(nfiles, by=di.order_by, rev=di.order_dir === :asc ? true : false)
		sort!(ndirs,  by=di.order_by, rev=di.order_dir === :asc ? true : false)
	end

	# Append the directory path to the contents -- so they have absolute paths.
	ndirs  = [joinpath(dir, d) for d in ndirs] 
	nfiles = [joinpath(dir, f) for f in nfiles] 


	# Merge the new files and directories with the current ones.
	if length(files) != 0 || length(dirs) != 0
		if di.by_depth 
			append!(files, nfiles)
			append!(dirs, ndirs)
			return (files, dirs)
		else
			append!(nfiles, files)
			append!(ndirs, dirs)
			return (nfiles, ndirs)
		end
	else
		return (nfiles, ndirs)
	end
end

#= Gets the next file and "state".
   Returns `nothing` if there is no next file; or,
   the tuple: (file, (di, files, dirs)).
   This is the form that our version of Base.iterate for `Directory` expects.
=#
function _get_next_state(di::DirItr, files::Vector{String}, dirs::Vector{String})
	while true
		if length(files) != 0  
			file = pop!(files)
			return (file, (di, files, dirs))
		end
		while length(dirs) != 0
			dir = pop!(dirs)
			st = _gather_files(di, dir, files, dirs)
			if st === nothing
				continue
			end
			files, dirs = st
			break
		end
		# If we exhausted dirs without finding files, we're done.
		if length(files) == 0
			return nothing
		end
	end
end

#= This function gets the next file to return.
   This function is called the first time in the iteration process.
   It reads the top level directory (specified by d.path) creating
   a vector of files and directories. It then calls get_next_state__
   which does the work of producing the next file and updating the state.
   The state consists of the two vectors: (files, dirs).
   Returns a two-tuple consisting of the next-file and the "state":
    ( next_file::String, (di::DirItr, files::Vector{String}, dirs::Vector{String}) )
=#
function Base.iterate(di::DirItr)

	# First check if the path exists.
	isdir(di.path) || throw("DirItr object, $di, does not have a valid/readable path.")

	# Get the files and sub-directories of `di.path`.
	result = _gather_files(di, di.path)
	
	# If _gather_files found nothing under d.path, return nothing -- we're done.
	if result === nothing
		return nothing
	end
	files, dirs = result

	# Return the next file and the state, which is of the form:  
	# (file, (di, files, dirs)) 
	st = _get_next_state(di, files, dirs)
	if st === nothing
		return nothing
	end
	return st
end

#= This function gets called on subsequent iterations...
   Returns a two-tuple consisting of the next-file and the "state":
   ( next_file::String, (di::DirItr, files::Vector{String}, dirs::Vector{String}) )
=#
function Base.iterate(di::DirItr, state)
	files = state[2]
	dirs = state[3]

	st = _get_next_state(di, files, dirs)
	if st === nothing
		return nothing
	end
	return st
end

end # module DirWalker

