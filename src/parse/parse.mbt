///| 消費ループ + スコープ認識局所分解
/// パーサのコアロジック — Reduce フェーズの実体

// ============================================================
// フラット化: Opts ツリーを ErasedNode 配列に展開
// ============================================================

///|
fn flatten(opts : @core.Opts) -> Array[@core.ErasedNode] {
  let result : Array[@core.ErasedNode] = []
  flatten_into(opts, result)
  result
}

///|
fn flatten_into(opts : @core.Opts, out : Array[@core.ErasedNode]) -> Unit {
  match opts {
    Node(node) => out.push(node)
    Array(arr) =>
      for item in arr {
        flatten_into(item, out)
      }
  }
}

// ============================================================
// 分類: OC (Option/Command) と P (Positional) に分ける
// ============================================================

///|
fn classify(
  nodes : Array[@core.ErasedNode],
) -> (Array[@core.ErasedNode], Array[@core.ErasedNode]) {
  let oc : Array[@core.ErasedNode] = []
  let p : Array[@core.ErasedNode] = []
  for node in nodes {
    match node.meta.kind {
      Option | Command => oc.push(node)
      Positional => p.push(node)
    }
  }
  (oc, p)
}

// ============================================================
// ヘルパー: arity に基づく値消費
// ============================================================

///|
/// arity > 0 かつ action が Value(None) の場合、次の引数を値として消費する。
/// 消費した場合は (final_action, true) を返す。消費しなかった場合は (action, false)。
fn resolve_value(
  node : @core.ErasedNode,
  action : @core.ReduceAction,
  args : Array[String],
  pos : Int,
) -> (@core.ReduceAction, Bool) raise @core.ParseError {
  if node.arity > 0 {
    match action {
      Value(None) => {
        let next_pos = pos + 1
        if next_pos >= args.length() {
          raise @core.ParseError::MissingValue(node.meta.name)
        }
        (@core.ReduceAction::Value(Some(args[next_pos])), true)
      }
      _ => (action, false)
    }
  } else {
    (action, false)
  }
}

///|
/// try_reduce + commit_reduce を実行する。
fn do_reduce(
  node : @core.ErasedNode,
  action : @core.ReduceAction,
) -> Unit raise @core.ParseError {
  let result = (node.try_reduce)(action, 0)
  match result {
    Some(rr) => (node.commit_reduce)(rr)
    None =>
      raise @core.ParseError::Custom(
        "internal error: reduce failed for " + node.meta.name,
      )
  }
}

// ============================================================
// メインループ: 引数消費ループ
// ============================================================

///|
pub fn parse(
  args : Array[String],
  root : @core.Opts,
) -> Unit raise @core.ParseError {
  let all_nodes = flatten(root)
  let (oc_nodes, p_nodes) = classify(all_nodes)
  // OC モード = true, P モード = false
  let mut oc_mode = true
  let mut pos = 0
  let mut p_index = 0
  // `--` セパレータで P モードに入った場合は true（Option 割り込み無効化）
  let mut force_positional = false
  // OC モードの option ノード（P モードでの Option 割り込み用）
  let option_nodes : Array[@core.ErasedNode] = []
  for node in oc_nodes {
    if node.meta.kind == @core.Kind::Option {
      option_nodes.push(node)
    }
  }
  while pos < args.length() {
    let arg = args[pos]
    if oc_mode {
      // `--` セパレータの処理: 以降は全て positional
      if arg == "--" {
        oc_mode = false
        force_positional = true
        pos = pos + 1
        continue
      }
      let resolve_result = @resolve.resolve(arg, oc_nodes)
      match resolve_result {
        Resolved(node, action) => {
          let (final_action, consumed_next) = resolve_value(
            node, action, args, pos,
          )
          do_reduce(node, final_action)
          if consumed_next {
            pos = pos + 1
          }
          // サブコマンドの場合はスコープ遷移
          if node.meta.kind == @core.Kind::Command {
            let children = (node.children)()
            let new_nodes : Array[@core.ErasedNode] = []
            for child in children {
              new_nodes.push(child)
            }
            // グローバルノードを親スコープから引き継ぎ
            for parent_node in all_nodes {
              if parent_node.meta.global {
                new_nodes.push(parent_node)
              }
            }
            let (new_oc, new_p) = classify(new_nodes)
            // Design rationale: MoonBit の let バインディングは再代入不可なので、
            // Array を clear + push で更新する。
            oc_nodes.clear()
            for n in new_oc {
              oc_nodes.push(n)
            }
            p_nodes.clear()
            for n in new_p {
              p_nodes.push(n)
            }
            option_nodes.clear()
            for n in oc_nodes {
              if n.meta.kind == @core.Kind::Option {
                option_nodes.push(n)
              }
            }
            oc_mode = true
            p_index = 0
          }
          pos = pos + 1
        }
        Unresolved => {
          if p_nodes.is_empty() {
            if arg.has_prefix("-") {
              raise @core.ParseError::UnknownOption(arg)
            } else {
              raise @core.ParseError::UnexpectedArgument(arg)
            }
          }
          // P モードに移行（pos は進めない、P モードで再処理）
          oc_mode = false
        }
      }
      // P モード
    } else if not(force_positional) && arg.has_prefix("-") && arg != "-" {
      // Option 割り込みを試みる（`--` 未使用時のみ）
      let resolve_result = @resolve.resolve(arg, option_nodes)
      match resolve_result {
        Resolved(node, action) => {
          let (final_action, consumed_next) = resolve_value(
            node, action, args, pos,
          )
          do_reduce(node, final_action)
          if consumed_next {
            pos = pos + 1
          }
          pos = pos + 1
        }
        Unresolved => {
          // P モード（`--` 以降）では positional にフォールバック
          if p_index >= p_nodes.length() {
            raise @core.ParseError::UnexpectedArgument(arg)
          }
          let p_node = p_nodes[p_index]
          let p_action = @core.ReduceAction::Value(Some(arg))
          do_reduce(p_node, p_action)
          p_index = p_index + 1
          pos = pos + 1
        }
      }
    } else {
      // positional 消費
      if p_index >= p_nodes.length() {
        raise @core.ParseError::UnexpectedArgument(arg)
      }
      let p_node = p_nodes[p_index]
      let p_action = @core.ReduceAction::Value(Some(arg))
      do_reduce(p_node, p_action)
      p_index = p_index + 1
      pos = pos + 1
    }
  }
}
