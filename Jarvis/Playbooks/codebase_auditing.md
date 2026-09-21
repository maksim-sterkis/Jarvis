# Playbook: Codebase Auditing & Multi-File Architecture Analysis
> Protocols for reviewing multi-file repositories, maintaining working memory, and cross-file synthesis.

## 1. Target Locking & Working Memory
- In Turn 1, identify the candidate files required to answer the question.
- Lock these files inside `<working_memory>`.
- Once locked, do not drop or change target files across turns.

## 2. Batch Inspection
- Use `read_multiple_files` to retrieve all candidate files in a single turn.
- Never fabricate or guess unread code.

## 3. Synthesis & Formatting
- Organize explanations logically by file or architectural layer.
- Use Markdown tables (`| Header | Header |`) to compare features or settings.
- Use `####` (H4) or `###` (H3) for subheadings.
