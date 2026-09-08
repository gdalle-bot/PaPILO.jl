using PaPILO
using Test
using SCIP
import SCIP_PaPILO_jll

const test_file = """
NAME          FLUGPL
ROWS
 N  KOSTEN  
 E  ANZ1    
 G  STD1    
 L  UEB1    
 E  ANZ2    
 G  STD2    
 L  UEB2    
 E  ANZ3    
 G  STD3    
 L  UEB3    
 E  ANZ4    
 G  STD4    
 L  UEB4    
 E  ANZ5    
 G  STD5    
 L  UEB5    
 E  ANZ6    
 G  STD6    
 L  UEB6    
COLUMNS
    STM1      KOSTEN            2700   ANZ1                 1
    STM1      STD1               150   UEB1               -20
    STM1      ANZ2               0.9
    MARK0000  'MARKER'                 'INTORG'
    ANM1      KOSTEN            1500   STD1              -100
    ANM1      ANZ2                 1
    MARK0001  'MARKER'                 'INTEND'
    UE1       KOSTEN              30   STD1                 1
    UE1       UEB1                 1
    MARK0002  'MARKER'                 'INTORG'
    STM2      KOSTEN            2700   ANZ2                -1
    STM2      STD2               150   UEB2               -20
    STM2      ANZ3               0.9
    ANM2      KOSTEN            1500   STD2              -100
    ANM2      ANZ3                 1
    MARK0003  'MARKER'                 'INTEND'
    UE2       KOSTEN              30   STD2                 1
    UE2       UEB2                 1
    MARK0004  'MARKER'                 'INTORG'
    STM3      KOSTEN            2700   ANZ3                -1
    STM3      STD3               150   UEB3               -20
    STM3      ANZ4               0.9
    ANM3      KOSTEN            1500   STD3              -100
    ANM3      ANZ4                 1
    MARK0005  'MARKER'                 'INTEND'
    UE3       KOSTEN              30   STD3                 1
    UE3       UEB3                 1
    MARK0006  'MARKER'                 'INTORG'
    STM4      KOSTEN            2700   ANZ4                -1
    STM4      STD4               150   UEB4               -20
    STM4      ANZ5               0.9
    ANM4      KOSTEN            1500   STD4              -100
    ANM4      ANZ5                 1
    MARK0007  'MARKER'                 'INTEND'
    UE4       KOSTEN              30   STD4                 1
    UE4       UEB4                 1
    MARK0008  'MARKER'                 'INTORG'
    STM5      KOSTEN            2700   ANZ5                -1
    STM5      STD5               150   UEB5               -20
    STM5      ANZ6               0.9
    ANM5      KOSTEN            1500   STD5              -100
    ANM5      ANZ6                 1
    MARK0009  'MARKER'                 'INTEND'
    UE5       KOSTEN              30   STD5                 1
    UE5       UEB5                 1
    MARK0010  'MARKER'                 'INTORG'
    STM6      KOSTEN            2700   ANZ6                -1
    STM6      STD6               150   UEB6               -20
    ANM6      KOSTEN            1500   STD6              -100
    MARK0011  'MARKER'                 'INTEND'
    UE6       KOSTEN              30   STD6                 1
    UE6       UEB6                 1
RHS
    RR        ANZ1                60   STD1              8000
    RR        STD2              9000   STD3              8000
    RR        STD4             10000   STD5              9000
    RR        STD6             12000
BOUNDS
 UP BB        ANM1                18
 LO BB        STM2                57
 UP BB        STM2                75
 UP BB        ANM2                18
 LO BB        STM3                57
 UP BB        STM3                75
 UP BB        ANM3                18
 LO BB        STM4                57
 UP BB        STM4                75
 UP BB        ANM4                18
 LO BB        STM5                57
 UP BB        STM5                75
 UP BB        ANM5                18
 LO BB        STM6                57
 UP BB        STM6                75
 UP BB        ANM6                18
ENDATA
"""

@testset "PaPILO.jl" begin
    input_instance = tempname() * ".mps"
    open(input_instance, "w") do f
        write(f, test_file)
    end
    presolved_instance = tempname() * ".mps"
    postsolve_file = tempname() * ".post"
    PaPILO.presolve_write_from_file(input_instance, postsolve_file, presolved_instance)
    @test isfile(presolved_instance)
    @test isfile(postsolve_file)
    
    # solve the problem using SCIP
    o = SCIP.Optimizer()
    SCIP.LibSCIP.SCIPreadProb(o, presolved_instance, C_NULL)
    SCIP.LibSCIP.SCIPsolve(o)
    reduced_sol = tempname() * ".sol"
    open(reduced_sol, "w") do f
        SCIP.LibSCIP.SCIPprintBestSol(o, Libc.FILE(f), 0)
    end
    original_sol = tempname() * ".sol"
    PaPILO.postsolve_from_file(postsolve_file, reduced_sol, original_sol)
    @test isfile(original_sol)
end

# A pure LP used to exercise dual postsolve. Dual postsolve is only available for
# problems without integer variables, so the MIP above cannot be used here.
#
#   min   x1 + 2 x2 + 3 x3 + 0.5 x4
#   s.t.  C1:  x1 + 3 x2      +   x4 >= 6
#         C2: 2 x1 +   x2               >= 8
#         C3:  x1        +   x3         <= 20
#         C4:        x2  + 2 x3         == 4
#         0 <= x1, x2, x3 <= 10,  0 <= x4 <= 3
const lp_test_file = """
NAME          DUALLP
ROWS
 N  COST
 G  C1
 G  C2
 L  C3
 E  C4
COLUMNS
    X1        COST             1.0   C1               1.0
    X1        C2               2.0   C3               1.0
    X2        COST             2.0   C1               3.0
    X2        C2               1.0   C4               1.0
    X3        COST             3.0   C3               1.0
    X3        C4               2.0
    X4        COST             0.5   C1               1.0
RHS
    RHS       C1               6.0   C2               8.0
    RHS       C3              20.0   C4               4.0
BOUNDS
 UP BND       X1              10.0
 UP BND       X2              10.0
 UP BND       X3              10.0
 UP BND       X4               3.0
ENDATA
"""

const lp_columns = ["X1", "X2", "X3", "X4"]
const lp_rows = ["C1", "C2", "C3", "C4"]
const lp_objective = Dict("X1" => 1.0, "X2" => 2.0, "X3" => 3.0, "X4" => 0.5)
# coefficients of each row, indexed by column name
const lp_matrix = Dict(
    "C1" => Dict("X1" => 1.0, "X2" => 3.0, "X4" => 1.0),
    "C2" => Dict("X1" => 2.0, "X2" => 1.0),
    "C3" => Dict("X1" => 1.0, "X3" => 1.0),
    "C4" => Dict("X2" => 1.0, "X3" => 2.0),
)
const lp_rhs = Dict("C1" => 6.0, "C2" => 8.0, "C3" => 20.0, "C4" => 4.0)
const lp_upper = Dict("X1" => 10.0, "X2" => 10.0, "X3" => 10.0, "X4" => 3.0)
const lp_sense = Dict("C1" => :geq, "C2" => :geq, "C3" => :leq, "C4" => :eq)

"""
Parse a PaPILO solution, dual solution or reduced costs file.

Returns the objective value and a dictionary of the named values. PaPILO omits entries
that are zero, so the dictionary is filled with explicit zeros for the given `names`.
"""
function parse_papilo_solution(path, names)
    values = Dict{String,Float64}(name => 0.0 for name in names)
    objective = nothing
    for line in eachline(path)
        parts = split(line)
        if isempty(parts)
            continue
        elseif parts[1] == "=obj="
            objective = parse(Float64, parts[2])
        else
            @assert parts[1] in names
            values[parts[1]] = parse(Float64, parts[2])
        end
    end
    return objective, values
end

@testset "dual postsolve" begin
    input_instance = tempname() * ".mps"
    open(input_instance, "w") do f
        write(f, lp_test_file)
    end
    presolved_instance = tempname() * ".mps"
    postsolve_file = tempname() * ".post"
    PaPILO.presolve_write_from_file(
        input_instance,
        postsolve_file,
        presolved_instance;
        dual_postsolve=true,
    )
    @test isfile(presolved_instance)
    @test isfile(postsolve_file)

    # solve the reduced problem with the LP solver bundled in the PaPILO executable,
    # which also produces the dual solution and the reduced costs of the reduced space
    reduced_sol = tempname() * ".sol"
    reduced_dual = tempname() * ".dual"
    reduced_costs = tempname() * ".rcost"
    SCIP_PaPILO_jll.papilo() do exe
        run(`$exe solve -f $presolved_instance -l $reduced_sol --dualsolution $reduced_dual -c $reduced_costs`)
    end
    @test isfile(reduced_sol)
    @test isfile(reduced_dual)
    @test isfile(reduced_costs)

    original_sol = tempname() * ".sol"
    original_dual = tempname() * ".dual"
    original_costs = tempname() * ".rcost"
    PaPILO.postsolve_from_file(
        postsolve_file,
        reduced_sol,
        original_sol;
        dual_reduced_solution=reduced_dual,
        costs_reduced_solution=reduced_costs,
        dualsolution=original_dual,
        reducedcosts=original_costs,
    )
    @test isfile(original_sol)
    @test isfile(original_dual)
    @test isfile(original_costs)

    primal_obj, x = parse_papilo_solution(original_sol, lp_columns)
    _, y = parse_papilo_solution(original_dual, lp_rows)
    _, d = parse_papilo_solution(original_costs, lp_columns)

    # the recovered solutions live in the original problem space, which is strictly
    # larger than the reduced one here
    @test length(x) == length(lp_columns)
    @test length(y) == length(lp_rows)
    @test length(d) == length(lp_columns)
    # the reduced problem really is smaller, so postsolve actually had work to do
    header = readlines(presolved_instance)
    reduced_ncols = parse(Int, split(only(filter(l -> startswith(l, "*COLUMNS:"), header)))[2])
    @test reduced_ncols < length(lp_columns)

    tol = 1e-6

    # primal feasibility
    for row in lp_rows
        activity = sum(coef * x[col] for (col, coef) in lp_matrix[row])
        if lp_sense[row] === :geq
            @test activity >= lp_rhs[row] - tol
        elseif lp_sense[row] === :leq
            @test activity <= lp_rhs[row] + tol
        else
            @test isapprox(activity, lp_rhs[row], atol=tol)
        end
    end
    for col in lp_columns
        @test x[col] >= -tol
        @test x[col] <= lp_upper[col] + tol
    end

    # dual feasibility: sign conditions for a minimization problem
    @test y["C1"] >= -tol
    @test y["C2"] >= -tol
    @test y["C3"] <= tol

    # stationarity / dual constraints: c_j - sum_i a_ij y_i == d_j
    for col in lp_columns
        lhs = lp_objective[col] - sum(get(lp_matrix[row], col, 0.0) * y[row] for row in lp_rows)
        @test isapprox(lhs, d[col], atol=tol)
    end

    # complementary slackness on the rows
    for row in lp_rows
        lp_sense[row] === :eq && continue
        activity = sum(coef * x[col] for (col, coef) in lp_matrix[row])
        @test isapprox(y[row] * (activity - lp_rhs[row]), 0.0, atol=tol)
    end

    # complementary slackness on the variable bounds: a nonzero reduced cost forces the
    # variable to sit at one of its bounds
    for col in lp_columns
        if abs(d[col]) > tol
            @test isapprox(x[col], 0.0, atol=tol) || isapprox(x[col], lp_upper[col], atol=tol)
        end
    end

    # strong duality, in the form implied by stationarity and complementary slackness:
    # c'x == b'y + d'x
    @test isapprox(
        sum(lp_objective[col] * x[col] for col in lp_columns),
        sum(lp_rhs[row] * y[row] for row in lp_rows) + sum(d[col] * x[col] for col in lp_columns),
        atol=tol,
    )

    # the reported objective matches the primal solution
    @test isapprox(primal_obj, sum(lp_objective[col] * x[col] for col in lp_columns), atol=tol)

    @testset "argument validation" begin
        # duals and reduced costs must be requested together
        @test_throws ArgumentError PaPILO.postsolve_from_file(
            postsolve_file, reduced_sol, original_sol; dual_reduced_solution=reduced_dual,
        )
        @test_throws ArgumentError PaPILO.postsolve_from_file(
            postsolve_file, reduced_sol, original_sol; costs_reduced_solution=reduced_costs,
        )
        # an output without the matching reduced-space input
        @test_throws ArgumentError PaPILO.postsolve_from_file(
            postsolve_file, reduced_sol, original_sol; dualsolution=original_dual,
        )
        @test_throws ArgumentError PaPILO.postsolve_from_file(
            postsolve_file, reduced_sol, original_sol; reducedcosts=original_costs,
        )
    end

    # A postsolve archive written with `dual_postsolve=true` stores dual information and
    # PaPILO requires it to be postsolved with the dual solution and the reduced costs;
    # passing only a primal solution to it crashes the executable. The default archive is
    # unaffected, which is what the round trip below checks.
    @testset "primal postsolve is unchanged" begin
        primal_presolved = tempname() * ".mps"
        primal_postsolve_file = tempname() * ".post"
        PaPILO.presolve_write_from_file(
            input_instance,
            primal_postsolve_file,
            primal_presolved,
        )
        primal_reduced_sol = tempname() * ".sol"
        SCIP_PaPILO_jll.papilo() do exe
            run(`$exe solve -f $primal_presolved -l $primal_reduced_sol`)
        end
        primal_only = tempname() * ".sol"
        PaPILO.postsolve_from_file(primal_postsolve_file, primal_reduced_sol, primal_only)
        @test isfile(primal_only)
        # the default (primal) pipeline finds the same optimum as the dual-aware one
        obj2, x2 = parse_papilo_solution(primal_only, lp_columns)
        @test isapprox(obj2, primal_obj, atol=tol)
        for col in lp_columns
            @test isapprox(x2[col], x[col], atol=tol)
        end

        # asking a primal-only archive for duals must not silently succeed: PaPILO exits
        # normally but writes no dual file
        missing_dual = tempname() * ".dual"
        missing_costs = tempname() * ".rcost"
        @test_throws ErrorException PaPILO.postsolve_from_file(
            primal_postsolve_file,
            primal_reduced_sol,
            primal_only;
            dual_reduced_solution=reduced_dual,
            costs_reduced_solution=reduced_costs,
            dualsolution=missing_dual,
            reducedcosts=missing_costs,
        )
        @test !isfile(missing_dual)
        @test !isfile(missing_costs)

        # a stale file left over from an earlier run must not mask that failure
        stale_dual = tempname() * ".dual"
        stale_costs = tempname() * ".rcost"
        write(stale_dual, "=obj=  0\n")
        write(stale_costs, "=obj=  0\n")
        @test_throws ErrorException PaPILO.postsolve_from_file(
            primal_postsolve_file,
            primal_reduced_sol,
            primal_only;
            dual_reduced_solution=reduced_dual,
            costs_reduced_solution=reduced_costs,
            dualsolution=stale_dual,
            reducedcosts=stale_costs,
        )
    end
end
