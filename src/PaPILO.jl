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

# Presolve parameters required for PaPILO to store dual postsolve information in the
# postsolve archive: dual reductions are only recorded when components detection and
# linear dependency detection are switched off and none of the presolvers substitution,
# sparsify, dualinfer and doubletoneq is enabled.
const DUAL_POSTSOLVE_SETTINGS = """
substitution.enabled = 0
sparsify.enabled = 0
dualinfer.enabled = 0
doubletoneq.enabled = 0
presolve.componentsmaxint = -1
presolve.detectlindep = 0
"""

"""
    presolve_write_from_file(problem_input::String, problem_postsolve::String, reduced_problem::String; dual_postsolve::Bool=false)

Given the file `problem_input` containing the original problem, presolve it,
store the presolved problem file in `reduced_problem` with the postsolve information written to `problem_postsolve` to then pass to the `postsolve_from_file` function

If `dual_postsolve` is `true`, presolving is restricted to the presolvers that support dual
postsolve (`DominatedColumns`, `DualFix`, `ParallelCols`, `ParallelRows`, `Propagation`,
`FixContinuous`, `ColSingleton` and `SingletonStuffing`) so that `problem_postsolve` also
stores the information needed to recover dual solutions and reduced costs with
[`postsolve_from_file`](@ref). The reduced problem is then usually larger than with the
default settings.

PaPILO only stores that information for problems without integer variables. If
`problem_input` has any, the archive silently stays primal-only and
[`postsolve_from_file`](@ref) throws when duals are requested from it.
"""
function presolve_write_from_file(problem_input::String, problem_postsolve::String, reduced_problem::String; dual_postsolve::Bool=false)
    @assert isfile(problem_input)
    args = String[]
    if dual_postsolve
        settings = tempname() * ".set"
        write(settings, DUAL_POSTSOLVE_SETTINGS)
        push!(args, "-p", settings)
    end
    SCIP_PaPILO_jll.papilo() do exe
        run(`$exe presolve -f $problem_input -v $problem_postsolve -r $reduced_problem $args`)
    end
end

"""
    postsolve_from_file(problem_postsolve, reduced_sol, original_sol; reduced_dual_sol=nothing, reduced_costs_sol=nothing, original_dual_sol=nothing, original_costs_sol=nothing)

Arguments:
- `problem_postsolve`: postsolve file produced by the presolve command
- `reduced_sol`: solution file to the reduced problem (produced by an external solver)
- `original_sol`: file name where to write the solution to the original problem 

Keyword arguments, mirroring the positional ones: `reduced_*` files describe the reduced
problem and are read, `original_*` files describe the original problem and are written.
- `reduced_dual_sol`: dual solution of the reduced problem
- `reduced_costs_sol`: reduced costs of the reduced problem
- `original_dual_sol`: file name where to write the dual solution to the original problem
- `original_costs_sol`: file name where to write the reduced costs of the original problem

All four use the same format as `reduced_sol` and `original_sol`: a line `=obj=` followed
by the objective value, then one line per entry with a name, its value and the objective
coefficient, as in

```
=obj=                                              10
C2                                                 0.5                  obj(8)
C4                                                 1.5                  obj(4)
```

Entries are named after the constraints for a dual solution and after the variables for
reduced costs, and entries equal to zero are omitted.

PaPILO recovers duals and reduced costs together, so `reduced_dual_sol` and
`reduced_costs_sol` must either both be given or both be omitted, and recovering either
requires `problem_postsolve` to have been written by [`presolve_write_from_file`](@ref)
with `dual_postsolve=true`. Such an archive in turn *must* be postsolved with the duals:
passing only a primal solution to it aborts PaPILO.
"""
function postsolve_from_file(problem_postsolve, reduced_sol, original_sol; reduced_dual_sol=nothing, reduced_costs_sol=nothing, original_dual_sol=nothing, original_costs_sol=nothing)
    @assert isfile(problem_postsolve)
    @assert isfile(reduced_sol)
    if (reduced_dual_sol === nothing) != (reduced_costs_sol === nothing)
        throw(ArgumentError("PaPILO recovers the dual solution and the reduced costs together, `reduced_dual_sol` and `reduced_costs_sol` must either both be provided or both be omitted"))
    end
    if original_dual_sol !== nothing && reduced_dual_sol === nothing
        throw(ArgumentError("`original_dual_sol` was requested but the dual solution of the reduced problem `reduced_dual_sol` is missing"))
    end
    if original_costs_sol !== nothing && reduced_costs_sol === nothing
        throw(ArgumentError("`original_costs_sol` was requested but the reduced costs of the reduced problem `reduced_costs_sol` are missing"))
    end
    args = String[]
    for (flag, file) in (("--dual-reduced-solution", reduced_dual_sol), ("--costs-reduced-solution", reduced_costs_sol))
        if file !== nothing
            @assert isfile(file)
            push!(args, flag, string(file))
        end
    end
    for (flag, file) in (("--dualsolution", original_dual_sol), ("-c", original_costs_sol))
        if file !== nothing
            # so that the check below cannot be fooled by a leftover file
            rm(file, force=true)
            push!(args, flag, string(file))
        end
    end
    SCIP_PaPILO_jll.papilo() do exe
        run(`$exe postsolve -v $problem_postsolve -u $reduced_sol -l $original_sol $args`)
    end
    # PaPILO exits successfully but writes no dual file when the archive does not contain
    # dual information, so the files themselves are what tells us whether it worked
    for file in (original_dual_sol, original_costs_sol)
        if file !== nothing && !isfile(file)
            error("PaPILO did not write $file because $problem_postsolve does not contain dual information, rerun `presolve_write_from_file` with `dual_postsolve=true`")
        end
    end
end

end
