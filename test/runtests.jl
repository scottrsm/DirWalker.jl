using DirWalker
using Test

@testset "DirWalker (Fidelity)" begin
    @test length(detect_ambiguities(DirWalker)) == 0
end


@testset "DirWalker (Count files)" begin
	# Create a directory iterator -- using the struct, DirItr.
	d = DirItr(joinpath(@__DIR__, "../"); by_depth=true, ordered=true)

	# Iterate over all files within the directory sub-tree.  
	cnt = 0
	for f in d
		cnt += 1
	end
	@test cnt == 8
end

