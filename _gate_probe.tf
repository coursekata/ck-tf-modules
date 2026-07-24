# Throwaway probe to verify the plan-capability gate trips in CI. Do not merge.
resource "null_resource" "gate_probe" {
  provisioner "local-exec" {
    command = "echo probe"
  }
}
