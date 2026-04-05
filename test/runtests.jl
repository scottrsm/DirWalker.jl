using DirWalker
using Test

@testset "DirWalker (Fidelity)" begin
    @test length(detect_ambiguities(DirWalker)) == 0
end


@testset "DirWalker (Count files)" begin
	# Create a fixture directory with known structure.
	fixture_dir = joinpath(@__DIR__, "fixture")
	rm(fixture_dir; force=true, recursive=true)
	mkpath(joinpath(fixture_dir, "sub1"))
	mkpath(joinpath(fixture_dir, "sub2", "nested"))
	mkpath(joinpath(fixture_dir, ".git"))
	write(joinpath(fixture_dir, "a.txt"), "a")
	write(joinpath(fixture_dir, "b.txt"), "b")
	write(joinpath(fixture_dir, "sub1", "c.txt"), "c")
	write(joinpath(fixture_dir, "sub2", "d.txt"), "d")
	write(joinpath(fixture_dir, "sub2", "nested", "e.txt"), "e")
	write(joinpath(fixture_dir, ".git", "config"), "git")

	# Create a directory iterator -- using the struct, DirItr.
	d = DirItr(fixture_dir; dprune=[raw"^\.git$"], by_depth=true, ordered=true)

	# Iterate over all files within the directory sub-tree.
	collected = String[]
	for f in d
		push!(collected, f)
	end

	# Should find exactly 5 files (a.txt, b.txt, c.txt, d.txt, e.txt) -- .git is pruned.
	@test length(collected) == 5
	@test all(f -> endswith(f, ".txt"), collected)
	@test !any(f -> contains(f, ".git"), collected)

	# Clean up fixture.
	rm(fixture_dir; force=true, recursive=true)
end

