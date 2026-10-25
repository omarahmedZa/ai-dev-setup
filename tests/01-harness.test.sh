test_harness_assertions_work() {
  new_sandbox
  assert_eq "a" "a"
  assert_file_missing "$HOME/nope"
  touch "$HOME/y"; assert_file_exists "$HOME/y"
}
