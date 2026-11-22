-- HEIST · Database fixes found on 21 Nov 2026. Run once in Supabase → SQL Editor. Safe to run again.
-- 1. Edit and delete for group expenses (groups-edit.sql was never run on the live database,
--    so "edit" and "delete" on a group expense fail for everyone right now).
-- 2. A member can only log an expense as paid by themselves (before, anyone could put someone else as the payer).
-- 3. Removes the test group left over from the October security check.

-- 1. Payer can edit and delete their expenses and splits
drop policy if exists "payer can update expense" on public.group_expenses;
create policy "payer can update expense" on public.group_expenses
  for update to authenticated
  using (exists (select 1 from public.group_members m where m.id = group_expenses.paid_by and m.user_id = (select auth.uid())))
  with check (exists (select 1 from public.group_members m where m.id = group_expenses.paid_by and m.user_id = (select auth.uid())));

drop policy if exists "payer can delete expense" on public.group_expenses;
create policy "payer can delete expense" on public.group_expenses
  for delete to authenticated
  using (exists (select 1 from public.group_members m where m.id = group_expenses.paid_by and m.user_id = (select auth.uid())));

drop policy if exists "payer can delete splits" on public.group_expense_splits;
create policy "payer can delete splits" on public.group_expense_splits
  for delete to authenticated
  using (exists (
    select 1 from public.group_expenses e join public.group_members m on m.id = e.paid_by
    where e.id = group_expense_splits.expense_id and m.user_id = (select auth.uid())));

alter table public.group_expenses replica identity full;
alter table public.group_expense_splits replica identity full;

-- 2. New expenses: you must be in the group AND be the payer
drop policy if exists "add expenses" on public.group_expenses;
create policy "add expenses" on public.group_expenses
  for insert to authenticated
  with check (
    is_group_member(group_id)
    and exists (select 1 from public.group_members m
                where m.id = group_expenses.paid_by and m.group_id = group_expenses.group_id and m.user_id = (select auth.uid())));

-- 3. Leftover test data ("RLS TEST delete me")
delete from public.group_expense_splits where expense_id in
  (select id from public.group_expenses where group_id = '5c725b26-d641-41ec-92a9-9be0ecc7212e');
delete from public.group_expenses where group_id = '5c725b26-d641-41ec-92a9-9be0ecc7212e';
delete from public.group_members where group_id = '5c725b26-d641-41ec-92a9-9be0ecc7212e';
delete from public.groups where id = '5c725b26-d641-41ec-92a9-9be0ecc7212e';
