using ConcaveHull: concave_hull
using Gadfly
using Random

import Colors
import MultivariateStats
import Plots

plot_cell_borders_chull(bmm_data::BmmData; kwargs...) = plot_cell_borders_chull(bmm_data.x, bmm_data.assignment; kwargs...)
function plot_cell_borders_chull(df_spatial::DataFrame, cell_labels::Array{Int, 1}; min_n_molecules::Int=3, kwargs...)
    point_arrs = [position_data(df_spatial[cell_labels .== label, :])' for label in unique(cell_labels)];
    chulls = [Array(hcat(concave_hull([vec(arr[i,:]) for i in 1:size(arr, 1)]).vertices...)) for arr in point_arrs if size(arr, 1) > min_n_molecules];
    chulls = vcat([hcat(DataFrame(ch', [:x, :y]), DataFrame(:c=>repeat([i], inner=size(ch, 2)))) for (i, ch) in enumerate(chulls)]...);

    return plot_cell_borders_polygons(df_spatial, chulls; kwargs...)
end

plot_cell_borders_density(bmm_data::BmmData; kwargs...) = plot_cell_borders_density(bmm_data.x, bmm_data.assignment; kwargs...)
function plot_cell_borders_density(df_spatial::DataFrame, cell_labels::Array{Int, 1}; min_n_molecules::Int=3, kwargs...)
    polygons = boundary_polygons(df_spatial, cell_labels, min_molecules_per_cell=min_n_molecules);
    return plot_cell_borders_polygons(df_spatial, polygons; kwargs...)
end

function plot_cell_borders_polygons(df_spatial::DataFrame, polygons::DataFrame, df_centers=nothing; point_size=5pt, color=:gene, edge_width=0.1pt,
                                    raster=false, center_size::Real=50.0, polygon_line_width=1pt)

    layers = [layer(polygons, x=:x, y=:y, group=:c, Geom.polygon(preserve_order=true, fill=false), Theme(line_width=polygon_line_width, lowlight_color=x->colorant"black")),
              layer(df_spatial, x=:x, y=:y, color=color, Theme(highlight_width=edge_width, point_size=point_size))]

    if df_centers !== nothing
        layers = vcat([layer(df_centers, x=:x, y=:y, size=repeat([center_size], inner=size(df_centers, 1)), Theme(default_color=colorant"black"))], layers)
    end

    fig = plot(
        layers...,
        Coord.cartesian(raster=raster, xmin=minimum(df_spatial[:x]), ymin=minimum(df_spatial[:y]), xmax=maximum(df_spatial[:x]), ymax=maximum(df_spatial[:y]))
    )

    return fig
end

function plot_num_of_cells_per_iterarion(tracer::Dict{String, Any})
    if !("n_components" in keys(tracer)) || length(tracer["n_components"]) == 0
        error("No data about #components per iteration was stored")
    end

    n_components_per_iter = hcat(collect.(values.(tracer["n_components"]))...);
    labels = collect(keys(tracer["n_components"][1]));

    n_components_per_iter = n_components_per_iter[sortperm(labels),:]
    labels = sort(labels)

    p = Plots.plot(legendtitle="Min #molecules", title="Convergence")
    for i in 1:size(n_components_per_iter, 1)
        p = Plots.plot!(n_components_per_iter[i,:], label="$(labels[i])")
    end

    return p
end

### Gene composition visualization

neighborhood_count_matrix(bmm_data::BmmData, k::Int) = neighborhood_count_matrix(bmm_data.x, k, maximum(bmm_data.x[:gene]))
function neighborhood_count_matrix(df::DataFrame, k::Int, n_genes::Int=maximum(df[:gene]))
    points = position_data(df);
    neighbors = knn(KDTree(points), points, k)[1];

    return hcat([prob_vec(df[:gene][ids], n_genes) for ids in neighbors]...)
end

function prob_vec(gene_ids::Array{Int, 1}, max_gene::Int, smooth::Int=0)
    probs = Array{Int}(zeros(max_gene))
    for id in gene_ids
        probs[id] += 1
    end

    probs .+= smooth
    return probs ./ sum(probs)
end

function gene_composition_transformation(count_matrix::Array{Float64, 2}; n_neighbors::Int=30, sample_size::Int=5000, seed::Int=42) # n_neighbors is for Isomap
    sample_size = min(sample_size, size(count_matrix, 2))
    Random.seed!(seed)
    count_matrix_sample = count_matrix[:,randperm(size(count_matrix, 2))[1:sample_size]]

    return fit(MultivariateStats.PCA, count_matrix_sample, maxoutdim=3);
end

function gene_composition_colors(count_matrix::Array{Float64, 2}, transformation)
    mtx_trans = MultivariateStats.transform(transformation, count_matrix);

    mtx_colors = mtx_trans .- mapslices(minimum, mtx_trans, dims=2)
    mtx_colors ./= mapslices(maximum, mtx_colors, dims=2);

    # return vec(mapslices(col -> "#" * hex(Colors.RGB(col...)), mtx_colors, dims=1))
    return vec(mapslices(col -> Colors.RGB(col...), mtx_colors, dims=1))
end

function shuffle_labels(labels::Array{Int})
    new_labs = deepcopy(labels)
    mask = (new_labs .!= 0)
    new_labs[mask] = shuffle(1:maximum(labels))[new_labs[mask]]
    return new_labs
end
