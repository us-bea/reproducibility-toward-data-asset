using Dates
using CSV, DataFrames, TidierData
using XLSX: XLSX, readtable
using HTTP: HTTP, URI, request
using unzip_jll: unzip
using Impute: locf
account_description = CSV.read(
    joinpath(DIR_PRJ, "data", "provided", "account_description.tsv"),
    DataFrame
)
detailed_agg = CSV.read(
    joinpath(DIR_PRJ, "data", "provided", "detailed_aggregates.tsv"),
    DataFrame
)
summary_industry = CSV.read(
    joinpath(DIR_PRJ, "data", "provided", "summary_industry.tsv"),
    DataFrame
)
"""
    ilpa_2025_04_25() -> DataFrame

Obtain the pre-release of the BEA/BLS Integrated Industry-level Production Account (ILPA) for the United States.
The estimates for labor compensation for each industry for 1997--2023.
"""
function ilpa_2025_04_25()
    filepath = joinpath(DIR_PRJ, "data", "bea", "BEA-BLS-industry-level-production-account-1997-2023.xlsx")
    output = @chain reduce(
        vcat,
        DataFrame(
            XLSX.readtable(
                filepath,
                sheetname,
                "A:AB",
                first_row=2
            )
        ) for sheetname in [
            "Labor_NoCol Compensation", "Labor_Col Compensation"
        ]
    ) begin
        @pivot_longer(
            Cols(r"\d{4}")
        )
        rename!(_, ["description", "year", "value"])
        @group_by(description, year)
        @summarize(
            value = as_integer(sum(value))
        )
        @ungroup
        @select(
            description = as_string(description),
            year = as_integer(year),
            value
        )
        @inner_join(
            @chain account_description begin
                @bind_rows(detailed_agg)
                @select(account, description)
            end
        )
        @select(account, year, value)
    end
    return output
end

"""
    ilpa_2023_09_29(latest::AbstractDataFrame) -> DataFrame

Obtain the pre-release of the BEA/BLS Integrated Industry-level Production Account (ILPA) for the United States.
The estimates for labor compensation for each industry for 1987--2021.
"""
function ilpa_2023_09_29(latest::AbstractDataFrame)
    filepath = joinpath(DIR_PRJ, "data", "bea", "BEA-BLS-industry-level-production-account-1987-2021.xlsx")
    @assert minimum(latest.year) == 1997
    output = @chain reduce(
        vcat,
        DataFrame(
            XLSX.readtable(
                filepath,
                sheetname,
                "A:L",
                first_row=2
            )
        ) for sheetname in [
            "Labor_NoCol Compensation", "Labor_Col Compensation"
        ]
    ) begin
        DataFrame
        @pivot_longer(
            Cols(r"\d{4}")
        )
        rename!(_, ["description", "year", "value"])
        @group_by(description, year)
        @summarize(
            value = as_integer(sum(value))
        )
        @ungroup
        @select(
            description = as_string(description),
            year = as_integer(year),
            value
        )
        @inner_join(
            @chain account_description begin
                @bind_rows(detailed_agg)
                @select(account, description)
            end
        )
        @arrange(account, year)
        @select(
            account,
            year,
            value
        )
        @group_by(account)
        @summarize(
            year,
            value = value / lag(value)
        )
        @filter(year < 1997)
        dropmissing!
        @arrange(account, desc(year))
        @group_by(account)
        @summarize(
            year,
            value = cumprod(value)
        )
        @arrange(account, year)
        @rename(Δ = value)
        @inner_join(
            @chain latest begin
                @group_by(account)
                @summarize(value = first(value))
            end
        )
        @select(
            account,
            year,
            value = as_integer(round(value / Δ))
        )
        @bind_rows(latest)
        @arrange(account, year)
    end
    return output
end

"""
    get_ilpa() -> DataFrame

Obtain the BEA/BLS Integrated Industry-level Production Account (ILPA) for the United States.
The result will report the labor compensation for each industry/year.
The default is the latest release from 2025-04-25 (1997 -- 2023).
"""
get_ilpa() = ilpa_2025_04_25()

"""
    get_ilpa(latest::AbstractDataFrame) -> DataFrame

Obtain the BEA/BLS Integrated Industry-level Production Account (ILPA) for the United States.
It will use the latest release that covers the years prior to the last year in the provided data.
The result will report the labor compensation for each industry/year based on best change.
"""
get_ilpa(latest::AbstractDataFrame) = ilpa_2023_09_29(latest)

"""
    ilpa2summary(ilpa::AbstractDataFrame)

Allocates the labor compensation from the ILPA accounts to the summary accounts.
It uses the relative compensation of employees from KLEMS.
It uses the GDP By Industry KLEMS 24Q2 release for 1997 -- 2023 and the historical version for 1987 -- 1996.
"""
function ilpa2summary(ilpa::AbstractDataFrame)
    klems = @chain XLSX.readtable(
        joinpath(DIR_PRJ, "data", "bea", "KLEMS.xlsx"),
        "TKG105-A",
        "A:AE",
        first_row=8
    ) begin
        DataFrame
        rename!(_, "#Empty" => "factor")
        @mutate(Line = as_integer(Line))
        @filter(Line ≤ 873)
        @mutate(factor = strip(factor))
        @mutate(
            description = case_when(
                lead(factor) == "Value added" => factor,
                true => Main.missing
            )
        )
        @mutate(
            description = strip(~locf(description))
        )
        @mutate(
            description = case_when(
                (description == "General government") & (Line < 847) => "GFG",
                (description == "Government enterprises") & (Line < 847) => "GFE",
                # (description == "General government") & (Line > 847) => "GSLG",
                (description == "Government enterprises") & (Line > 847) => "GSLE",
                true => description
            )
        )
        @inner_join(account_description)
        @select(
            account,
            factor = case_when(
                description == factor => "go",
                true => factor
            ),
            Cols(r"^\d{4}$")
        )
        @pivot_longer(
            Not([:account, :factor])
        )
        @select(
            account,
            factor = case_when(
                factor == "Value added" => "va",
                factor == "Compensation of employees" => "coe",
                factor == "Taxes on production and imports less subsidies" => "ntop",
                factor == "Gross operating surplus" => "gos",
                factor == "Intermediate inputs" => "ii",
                factor == "Energy inputs" => "ei",
                factor == "Materials inputs" => "mi",
                factor == "Purchased-services inputs" => "ps",
                true => factor
            ),
            year = as_integer(variable),
            value = as_integer(value)
        )
        dropmissing!
        @filter(factor == "coe")
        @select(account, year, value)
    end
    #=
        KLEMS historical uses the following aggregates:
        - 44RT
        - 531
        - 622OH
        - GFG
        for a total match of 65 and 6 that have to be estimated.
    =#
    klems_hist = @chain XLSX.readtable(
        joinpath(DIR_PRJ, "data", "bea", "GDPbyInd_KLEMS_1963-1997.xlsx"),
        "CompGO",
        "A:AK",
        first_row=6
    ) begin
        DataFrame
        rename!(_, "missing" => "factor")
        @mutate(Line = as_integer(Line))
        @filter(Line < 883)
        dropmissing!
        @mutate(factor = strip(factor))
        @mutate(
            factor = case_when(
                Line == 695 => "Value added",
                Line == 696 => "Compensation of employees",
                Line == 697 => "Taxes on production and imports less subsidies",
                Line == 698 => "Gross operating surplus",
                Line == 699 => "Intermediate inputs",
                Line == 700 => "Energy inputs",
                Line == 701 => "Materials inputs",
                Line == 702 => "Purchased-services inputs",
                true => factor
            )
        )
        @mutate(
            factor = case_when(
                Line == 820 => "GFG",
                Line == 847 => "GFE",
                # Line == 865 => "GSLG",
                Line == 874 => "GSLE",
                true => factor
            )
        )
        @mutate(
            account = case_when(
                lead(factor) == "Value added" => factor,
                true => Main.missing
            )
        )
        @mutate(
            description = strip(~locf(account))
        )
        @select(
            Line,
            description,
            factor = case_when(
                description == factor => "go",
                true => factor
            ),
            Cols(r"^\d{4}$")
        )
        @mutate(
            description = case_when(
                #= Historical =#
                (description == "General government") & (Line < 847) => "GFG",
                (description == "Government enterprises") & (Line < 847) => "GFE",
                # (description == "General government") & (Line > 847) => "GSLG",
                (description == "Government enterprises") & (Line > 847) => "GSLE",
                true => description
            )
        )
        @inner_join(
            @chain account_description begin
                @bind_rows(
                    DataFrame(
                        account=[
                            "Retail trade",
                            "Hospitals and nursing and residential care facilities",
                            "GFG",
                        ],
                        description=[
                            "44RT",
                            "622HO",
                            "GFG"
                        ],
                    )
                )
                @bind_rows(
                    @filter(detailed_agg, !startswith(account, 'G'))
                )
            end
        )
        @pivot_longer(
            Not([:account, :factor])
        )
        @select(
            account,
            factor = case_when(
                factor == "Value added" => "va",
                factor == "Compensation of employees" => "coe",
                factor == "Taxes on production and imports less subsidies" => "ntop",
                factor == "Gross operating surplus" => "gos",
                factor == "Intermediate inputs" => "ii",
                factor == "Energy inputs" => "ei",
                factor == "Materials inputs" => "mi",
                factor == "Purchased-services inputs" => "ps",
                true => factor
            ),
            year = as_integer(variable),
            value = as_integer(value)
        )
        dropmissing!
        @filter(factor == "coe")
        @arrange
    end
    klems_hist_summary = @chain klems begin
        @filter(year == 1997)
        @inner_join(
            x = @chain account_description begin
                @select(account, detailed_agg)
                dropmissing!
                @filter(detailed_agg ∈ ["44RT", "531", "622HO"])
                @bind_rows(
                    DataFrame(account=["GFGD", "GFGN"], detailed_agg="GFG")
                )
            end
        )
        @inner_join(
            _,
            @chain _ begin
                @group_by(detailed_agg)
                @summarize(den = sum(value))
            end
        )
        @select(account, detailed_agg, share = value / den)
        @inner_join(
            @chain klems_hist begin
                @rename(detailed_agg = account)
            end
        )
        @select(
            account,
            year,
            value = as_integer(round(value * share))
        )
        @bind_rows(
            @chain klems_hist begin
                @inner_join(account_description)
                @select(account, year, value)
            end
        )
        @arrange
    end
    klems_87_23 = @chain klems_hist_summary begin
        @group_by(account)
        @summarize(
            year,
            value = value / lag(value)
        )
        @filter(year < 1997)
        dropmissing!
        @arrange(account, desc(year))
        @group_by(account)
        @summarize(
            year,
            value = cumprod(value)
        )
        @arrange(account, year)
        @rename(Δ = value)
        @inner_join(
            @chain klems begin
                @group_by(account)
                @summarize(value = first(value))
            end
        )
        @select(
            account,
            year,
            value = as_integer(round(value / Δ))
        )
        @bind_rows(klems)
        @arrange(account, year)
    end
    output = @chain klems_87_23 begin
        @inner_join(
            @chain account_description begin
                @filter(!ismissing(detailed_agg))
                @select(account, detailed_agg)
            end
        )
        @inner_join(
            _,
            @chain _ begin
                @group_by(detailed_agg, year)
                @summarize(den = sum(value))
                @ungroup
            end
        )
        @select(
            account = detailed_agg,
            detailed = account,
            year,
            share = value / den
        )
        @inner_join(ilpa)
        @select(
            account = detailed,
            year,
            value = as_integer(round(value * share))
        )
        @bind_rows(
            @chain ilpa begin
                @inner_join(
                    @chain account_description begin
                        @filter(ismissing(detailed_agg))
                        @select(account)
                    end
                )
            end
        )
        @arrange
    end
    return output
end

"""
    labor_outyear(labor_compensation::AbstractDataFrame)

Apply the best change to labor compensation using the wages and salaries increase by sector.
Uses NIPA 2.2 from 2024Q3V3 (2025-03-28).
"""
function labor_outyear(labor_compensation::AbstractDataFrame)
    sec2_2 = @chain XLSX.readtable(
        joinpath(DIR_PRJ, "data", "bea", "Section2All_xls.xlsx"),
        "T20200B-A",
        "A:AE",
        first_row=8
    ) begin
        DataFrame
        @rename(sector = `#Empty`)
        @pivot_longer(Cols(r"^\d{4}$"))
        @mutate(sector = strip(sector))
        @group_by(sector)
        combine(_) do subdf
            last(@select(subdf, year = variable, value = as_integer(value)), 2)
        end
        @pivot_wider(
            names_from = sector,
            values_from = value
        )
        @mutate(
            `Non-Manufacturing` = `Goods-producing industries` - Manufacturing
        )
        @pivot_longer(
            cols = Not(:year),
            names_to = industry
        )
        @group_by(industry)
        @summarize(year = as_integer(year), Δ = lead(value) / value)
        dropmissing!
        @mutate(industry = replace(industry, "\\1\\" => ""))
        @inner_join(summary_industry)
        @select(account, year, Δ)
        @inner_join(labor_compensation)
        @select(
            account,
            year = year + 1,
            value = as_integer(round(value * Δ))
        )
    end
    output = @chain labor_compensation begin
        @bind_rows(sec2_2)
        @arrange
    end
    return output
end

"""
    get_go_basic_514_5415() -> DataFrame

Return the gross output at basic prices for the composite industry 514/5415 from 1987 -- 2023.
"""
function get_go_basic_514_5415()
    output = @chain XLSX.readtable(
        joinpath(DIR_PRJ, "data", "bea", "BEA-BLS-industry-level-production-account-1987-2021.xlsx"),
        "Gross Output",
        "A:K",
        first_row=2,
    ) begin
        DataFrame
        @pivot_longer(
            Cols(r"^\d{4}$"),
            names_to = year
        )
        @bind_rows(
            @chain XLSX.readtable(
                joinpath(DIR_PRJ, "data", "bea", "BEA-BLS-industry-level-production-account-1997-2023.xlsx"),
                "Gross Output",
                first_row=2
            ) begin
                DataFrame
                @pivot_longer(
                    Cols(r"^\d{4}$"),
                    names_to = year
                )
            end
        )
        @inner_join(
            @chain account_description begin
                @filter(account ∈ ["514", "5415"])
                @select(account, `Industry Description` = description)
            end
        )
        @select(
            account,
            year = as_integer(year),
            value = as_integer(value)
        )
        @group_by(year)
        @summarize(value = sum(value))
    end
    return output
end

"""
    compute_go_labor_514_5415(
        labor::AbstractDataFrame,
        go::AbstractDataFrame
    ) -> DataFrame

Computes the ten-year lagged simple moving average of the ratio of gross output over labor compensation using the ILPA releases.
"""
function compute_go_labor_514_5415(labor::AbstractDataFrame, go::AbstractDataFrame)
    output = @chain labor begin
        @filter(account ∈ ["514", "5415"])
        @group_by(year)
        @summarize(L = sum(value))
        @inner_join(
            go
        )
        @select(year, go_l = value / L)
        @filter(year ≥ 1987)
        crossjoin(@select(_, year), @select(_, year, go_l), makeunique = true)
        @filter((year - year_1) ∈ 0:9) # Ten-year lagged simple moving average
        @group_by(year)
        @summarize(fpcaf = mean(go_l))
    end
    return output
end

"""
    prices_ii(labor::AbstractDataFrame) -> DataFrame

Returns the price contribution of labor and intermediate inputs for the composite industry 514/5415 from 1987--2023 based on 514/5415.
The price effect for labor must be included later from the change in cost per labor.
"""
function prices_ii(labor::AbstractDataFrame)
    ii_comp_514_5415_87_96 = @chain XLSX.readtable(
        joinpath(DIR_PRJ, "data", "bea", "GDPbyInd_II_1947-1997.xlsx"),
        "II",
        "A:BA",
        first_row=6
    ) begin
        DataFrame
        rename!(_, "missing" => "description")
        @filter(!ismissing(description))
        @mutate(description = strip(description))
        @inner_join(
            @chain account_description begin
                @filter(account ∈ ["514", "5415"])
            end
        )
        @pivot_longer(
            Cols(r"^\d{4}$"),
            names_to = year,
            values_to = ii
        )
        @select(
            account,
            year = as_integer(year),
            value = as_integer(ii)
        )
        dropmissing!
        @filter(year ∈ 1987:1996)
        dropmissing!
        @arrange(account, desc(year))
        @arrange(account, year)
    end
    ii_Δp_514_5415_64_96 = @chain XLSX.readtable(
        joinpath(DIR_PRJ, "data", "bea", "GDPbyInd_II_1947-1997.xlsx"),
        "ChainPriceIndexes",
        "A:BA",
        first_row=6
    ) begin
        DataFrame
        rename!(_, "missing" => "description")
        @filter(!ismissing(description))
        @mutate(description = strip(description))
        @inner_join(
            @chain account_description begin
                @filter(account ∈ ["514", "5415"])
            end
        )
        @pivot_longer(
            Cols(r"^\d{4}$"),
            names_to = year,
            values_to = :Δ
        )
        @select(
            account,
            year = as_integer(year),
            value = as_float(Δ)
        )
        dropmissing!
        @group_by(account)
        @summarize(
            year,
            value = Main.log(value / lag(value))
        )
        dropmissing!
    end
    ii_comp_514_5415_97_24 = @chain XLSX.readtable(
        joinpath(DIR_PRJ, "data", "bea", "IntermediateInputs.xlsx"),
        "TII105-A",
        "A:AE",
        first_row=8
    ) begin
        DataFrame
        rename!(_, "#Empty" => "description")
        @filter(!ismissing(description))
        @mutate(description = strip(description))
        @inner_join(
            @chain account_description begin
                @filter(account ∈ ["514", "5415"])
            end
        )
        @pivot_longer(
            Cols(r"^\d{4}$"),
            names_to = year,
            values_to = ii
        )
        @select(
            account,
            year = as_integer(year),
            value = as_integer(ii)
        )
        dropmissing!
    end
    ii_comp = @chain ii_comp_514_5415_87_96 begin
        @bind_rows(ii_comp_514_5415_97_24)
    end
    ii_Δp_514_5415_97_24 = @chain XLSX.readtable(
        joinpath(DIR_PRJ, "data", "bea", "IntermediateInputs.xlsx"),
        "TII104-A",
        "A:AE",
        first_row=8
    ) begin
        DataFrame
        rename!(_, "#Empty" => "description")
        @filter(!ismissing(description))
        @mutate(description = strip(description))
        @inner_join(
            @chain account_description begin
                @filter(account ∈ ["514", "5415"])
            end
        )
        @pivot_longer(
            Cols(r"^\d{4}$"),
            names_to = year,
            values_to = :Δ
        )
        @select(
            account,
            year = as_integer(year),
            value = as_float(Δ)
        )
        @group_by(account)
        @summarize(
            year,
            value = Main.log(value / lag(value))
        )
        dropmissing!
    end
    output = @chain ii_comp begin
        @bind_rows(
            @chain labor begin
                @filter(account ∈ ["514", "5415"])
                @group_by(year)
                @summarize(account = "L", value = sum(value))
            end
        )
        @inner_join(
            _,
            @chain _ begin
                @group_by(year)
                @summarize(den = sum(value))
            end
        )
        @select(account, year, share = value / den, den)
        @left_join(
            _,
            @chain ii_Δp_514_5415_64_96 begin
                @bind_rows(ii_Δp_514_5415_97_24)
            end
        )
        @mutate(wgt = share * value)
        @mutate(
            factor = case_when(
                account ∈ ["514", "5415"] => "EMS",
                true => account
            )
        )
        @mutate(wgt_ = case_when(
            factor == "L" => share, true => 1.0)
        )
        @group_by(year, factor)
        @summarize(
            wgt = only(~unique(wgt_)),
            Δp = sum(wgt)
        )
        @ungroup
        # @filter(year < 2025)
    end
    return output
end

"""
    representative_productivity() -> DataFrame

Returns the negative of the 5-year moving average of total factor productivity based on the ILPA for 1987--2023.
"""
function representative_productivity()
    productivity = @chain XLSX.readtable(
        joinpath(DIR_PRJ, "data", "bea", "BEA-BLS-industry-level-production-account-1987-2021.xlsx"),
        "TFP",
        "A:M",
        first_row=2,
    ) begin
        DataFrame
        @pivot_longer(
            Cols(r"^\d{4}$"),
            names_to = year
        )
        @inner_join(
            @chain account_description begin
                @filter(account ∈ ["514", "5415"])
                @select(account, `Industry Description` = description)
            end
        )
        @group_by(account)
        @summarize(
            year = as_integer(year),
            value = Main.log(value / lag(value))
        )
        dropmissing!
        @bind_rows(
            @chain XLSX.readtable(
                joinpath(DIR_PRJ, "data", "bea", "BEA-BLS-industry-level-production-account-1997-2023.xlsx"),
                "Integrated TFP Index",
                first_row=2
            ) begin
                DataFrame
                @pivot_longer(
                    Cols(r"^\d{4}$"),
                    names_to = year
                )
                @inner_join(
                    @chain account_description begin
                        @filter(account ∈ ["514", "5415"])
                        @select(account, `Industry Description` = description)
                    end
                )
                @group_by(account)
                @summarize(
                    year = as_integer(year),
                    value = Main.log(value / lag(value))
                )
                dropmissing!
            end
        )
        @arrange
    end
    shares = @chain XLSX.readtable(
        joinpath(DIR_PRJ, "data", "bea", "BEA-BLS-industry-level-production-account-1987-2021.xlsx"),
        "Gross Output",
        "A:K",
        first_row=2,
    ) begin
        DataFrame
        @pivot_longer(
            Cols(r"^\d{4}$"),
            names_to = year
        )
        @bind_rows(
            @chain XLSX.readtable(
                joinpath(DIR_PRJ, "data", "bea", "BEA-BLS-industry-level-production-account-1997-2023.xlsx"),
                "Gross Output",
                first_row=2
            ) begin
                DataFrame
                @pivot_longer(
                    Cols(r"^\d{4}$"),
                    names_to = year
                )
            end
        )
        @inner_join(
            @chain account_description begin
                @filter(account ∈ ["514", "5415"])
                @select(account, `Industry Description` = description)
            end
        )
        @select(
            account,
            year = as_integer(year),
            value = as_integer(value)
        )
        @inner_join(
            _,
            @chain _ begin
                @group_by(year)
                @summarize(den = sum(value))
            end
        )
        @select(account, year, share = value / den)
    end
    output = @chain productivity begin
        @inner_join(shares)
        @mutate(wgt = value * share)
        @group_by(year)
        @summarize(tfp = sum(wgt))
        crossjoin(@select(_, year), _, makeunique=true)
        @filter(year - year_1 ∈ 0:5)
        @group_by(year)
        @summarize(factor = "TFP", Δp = -mean(tfp))
    end
    return output
end