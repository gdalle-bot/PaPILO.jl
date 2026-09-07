# Copyright 2022 Zuse Institute Berlin

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at

#     http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

module PaPILO

import SCIP_PaPILO_jll

"""
    write_dual_postsolve_settings(io, calculate_basis_for_dual::Bool)

Write the presolve parameter settings that PaPILO requires in order to store dual
postsolve information in the postsolve archive.

PaPILO only records dual reductions when the problem is linear (no integer variables),
components detection and linear dependency detection are switched off, and none of the
presolvers `substitution`, `sparsify`, `dualinfer` and `doubletoneq` are enabled.
"""
function write_dual_postsolve_settings(io, calculate_basis_for_dual::Bool)
    println(io, "substitution.enabled = 0")
    println(io, "sparsify.enabled = 0")
    println(io, "dualinfer.enabled = 0")
    println(io, "doubletoneq.enabled = 0")
    println(io, "presolve.componentsmaxint = -1")
    println(io, "presolve.detectlindep = 0")
    println(io, "calculate_basis_for_dual = ", calculate_basis_for_dual ? 1 : 0)
    return
end

"""
    presolve_write_from_file(problem_input::String, problem_postsolve::String, reduced_problem::String; dual_postsolve::Bool=false, calculate_basis_for_dual::Bool=true)

Given the file `problem_input` containing the original problem, presolve it,
store the presolved problem file in `reduced_problem` with the postsolve information written to `problem_postsolve` to then pass to the `postsolve_from_file` function

Keyword arguments:
- `dual_postsolve`: if `true`, presolve is restricted to the presolvers that support dual
  postsolve so that the postsolve archive also stores the information needed to recover
  dual solutions, reduced costs and basis information. Required if the corresponding
  arguments of [`postsolve_from_file`](@ref) are used.
- `calculate_basis_for_dual`: only used when `dual_postsolve` is `true`. If `true`
  (the default, matching PaPILO), presolving steps tightening the variable bounds are
  only applied when they fix the variable, which is needed to recover a basis.

Dual postsolve is only supported for continuous (linear) problems and only for a subset of
the presolvers: `DominatedColumns`, `DualFix`, `ParallelCols`, `ParallelRows`,
`Propagation`, `FixContinuous`, `ColSingleton` and `SingletonStuffing`. If PaPILO cannot
activate it for the given problem, a warning is emitted and the archive only supports
primal postsolve.
"""
function presolve_write_from_file(problem_input::String, problem_postsolve::String, reduced_problem::String; dual_postsolve::Bool=false, calculate_basis_for_dual::Bool=true)
    @assert isfile(problem_input)
    if !dual_postsolve
        SCIP_PaPILO_jll.papilo() do exe
            run(`$exe presolve -f $problem_input -v $problem_postsolve -r $reduced_problem`)
        end
        return
    end
    settings = tempname() * ".set"
    open(settings, "w") do f
        write_dual_postsolve_settings(f, calculate_basis_for_dual)
    end
    log = IOBuffer()
    SCIP_PaPILO_jll.papilo() do exe
        run(pipeline(`$exe presolve -f $problem_input -v $problem_postsolve -r $reduced_problem -p $settings`, stdout=log, stderr=log))
    end
    output = String(take!(log))
    print(output)
    if !occursin("dual-postsolve activated", output)
        @warn "PaPILO could not activate dual postsolve for this problem, the postsolve archive only supports primal postsolve. Dual postsolve requires a problem without integer variables."
    end
    return
end

"""
    postsolve_from_file(problem_postsolve, reduced_sol, original_sol; dual_reduced_sol=nothing, costs_reduced_sol=nothing, basis_reduced_sol=nothing, dual_sol=nothing, reduced_costs=nothing, basis=nothing)

Arguments:
- `problem_postsolve`: postsolve file produced by the presolve command
- `reduced_sol`: solution file to the reduced problem (produced by an external solver)
- `original_sol`: file name where to write the solution to the original problem 

Keyword arguments for the reduced problem (produced by an external solver):
- `dual_reduced_sol`: dual solution of the reduced problem
- `costs_reduced_sol`: reduced costs of the reduced problem
- `basis_reduced_sol`: basis (`.bas`) of the reduced problem

Keyword arguments for the original problem (written by PaPILO):
- `dual_sol`: file name where to write the dual solution to the original problem
- `reduced_costs`: file name where to write the reduced costs of the original problem
- `basis`: file name where to write the basis of the original problem

PaPILO recovers duals and reduced costs together, so `dual_reduced_sol` and
`costs_reduced_sol` must either both be given or both be omitted. Recovering the dual
solution requires the postsolve archive to have been written by
[`presolve_write_from_file`](@ref) with `dual_postsolve=true`, which restricts presolving
to `DominatedColumns`, `DualFix`, `ParallelCols`, `ParallelRows`, `Propagation`,
`FixContinuous`, `ColSingleton` and `SingletonStuffing`. Recovering a basis additionally
requires `calculate_basis_for_dual=true` at presolve time, which restricts bound
tightenings to those that fix a variable.

!!! warning
    `basis_reduced_sol` is currently unusable with the PaPILO 3.0.1 executable shipped by
    `SCIP_PaPILO_jll`: reading a reduced-space basis aborts the executable with a
    `std::bad_alloc`, including for basis files written by PaPILO itself. The keyword is
    plumbed through so that it works once the upstream issue is fixed. The dual solution
    and the reduced costs are unaffected.
"""
function postsolve_from_file(problem_postsolve, reduced_sol, original_sol; dual_reduced_sol=nothing, costs_reduced_sol=nothing, basis_reduced_sol=nothing, dual_sol=nothing, reduced_costs=nothing, basis=nothing)
    @assert isfile(problem_postsolve)
    @assert isfile(reduced_sol)
    if (dual_reduced_sol === nothing) != (costs_reduced_sol === nothing)
        throw(ArgumentError("PaPILO recovers the dual solution and the reduced costs together, `dual_reduced_sol` and `costs_reduced_sol` must either both be provided or both be omitted"))
    end
    if dual_sol !== nothing && dual_reduced_sol === nothing
        throw(ArgumentError("`dual_sol` was requested but the dual solution of the reduced problem `dual_reduced_sol` is missing"))
    end
    if reduced_costs !== nothing && costs_reduced_sol === nothing
        throw(ArgumentError("`reduced_costs` was requested but the reduced costs of the reduced problem `costs_reduced_sol` are missing"))
    end
    if basis !== nothing && basis_reduced_sol === nothing
        throw(ArgumentError("`basis` was requested but the basis of the reduced problem `basis_reduced_sol` is missing"))
    end
    if basis_reduced_sol !== nothing && dual_reduced_sol === nothing
        throw(ArgumentError("`basis_reduced_sol` can only be used together with `dual_reduced_sol` and `costs_reduced_sol`"))
    end
    for file in (dual_reduced_sol, costs_reduced_sol, basis_reduced_sol)
        file === nothing || @assert isfile(file)
    end
    args = String[]
    for (flag, file) in (
        ("--dual-reduced-solution", dual_reduced_sol),
        ("--costs-reduced-solution", costs_reduced_sol),
        ("--basis-reduced-solution", basis_reduced_sol),
        ("--dualsolution", dual_sol),
        ("-c", reduced_costs),
        ("-w", basis),
    )
        if file !== nothing
            push!(args, flag, string(file))
        end
    end
    SCIP_PaPILO_jll.papilo() do exe
        run(`$exe postsolve -v $problem_postsolve -u $reduced_sol -l $original_sol $args`)
    end
end

end
