"""
    DataAssets

The module to compute the deliverables for the BEA data and databases experimental account.
"""
module DataAssets
    using Dates
    using CSV, DataFrames, TidierData
    using XLSX: XLSX, readtable
    using HTTP: HTTP, URI, request
    using unzip_jll: unzip
    using Impute: locf
    """
        DIR_PRJ
    Project directory based on the Git top level.
    """
    const DIR_PRJ = string(strip(read(`git rev-parse --show-toplevel`, String)))
    export
        get_ilpa,
        ilpa2summary,
        labor_outyear,
        get_go_basic_514_5415,
        compute_go_labor_514_5415,
        prices_ii,
        representative_productivity
    for file in filter!(!isequal(replace(@__FILE__, string(@__DIR__, '/') => "")), readdir(@__DIR__))
        include(joinpath(@__DIR__, file))
    end
end
