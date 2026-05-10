import SoLean.Compiler
import SoLean.Examples.CounterYul

namespace SoLean
namespace Examples
namespace CounterCompiler

def counterFunction : Source.Function :=
  { paramName := "amount",
    body :=
      .seq
        (.require (.gt .param (.const UInt256.zero)))
        (.seq
          (.assign Counter.xSlot (.add (.slot Counter.xSlot) .param))
          (.assert (.ge (.slot Counter.xSlot) .param))) }

theorem counter_instantiates_to_existing_model (amount : UInt256) :
    Source.instantiateFunction counterFunction amount =
      Counter.incProgram amount := by
  rfl

theorem compile_counter_eq_counter_yul :
    Compiler.compileFunction counterFunction =
      some CounterYul.counterProgram := by
  rfl

/--
The tiny compiler emits a restricted Yul Counter program that reproduces every
successful execution of the existing SoLean Counter model.
-/
theorem compiled_counter_refines_solean_success
    (env : Env) (storage finalStorage : Storage) (amount : UInt256)
    (h :
      exec env (Source.instantiateFunction counterFunction amount) storage =
        ExecResult.success finalStorage) :
    match Compiler.compileFunction counterFunction with
    | some program => Yul.execFunction program amount storage =
        Yul.ExecResult.success finalStorage
    | none => False := by
  rw [counter_instantiates_to_existing_model] at h
  rw [compile_counter_eq_counter_yul]
  exact CounterYul.counter_refines_solean_success env storage finalStorage amount h

/--
The compiled restricted Yul Counter program inherits the Counter assertion
safety property for successful executions.
-/
theorem compiled_counter_success_assertion
    (storage finalStorage : Storage) (amount : UInt256)
    (h :
      match Compiler.compileFunction counterFunction with
      | some program => Yul.execFunction program amount storage =
          Yul.ExecResult.success finalStorage
      | none => False) :
    amount <= finalStorage.read Counter.xSlot := by
  rw [compile_counter_eq_counter_yul] at h
  exact CounterYul.counter_yul_success_assertion storage finalStorage amount h

end CounterCompiler
end Examples
end SoLean
