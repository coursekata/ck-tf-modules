# fixture

Test fixture for [`context-schema`](../..)'s provider-compatibility suite. It configures a `context`
provider from the schema's emitted outputs and renders a label, so the suite can prove those
constants are accepted as valid provider configuration (not just well-formed data).

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.11.6, < 2.0 |
| <a name="requirement_context"></a> [context](#requirement\_context) | ~> 0.5.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_context"></a> [context](#provider\_context) | ~> 0.5.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [context_label.this](https://registry.terraform.io/providers/cloudposse/context/latest/docs/data-sources/label) | data source |
| [context_tags.this](https://registry.terraform.io/providers/cloudposse/context/latest/docs/data-sources/tags) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_properties"></a> [properties](#input\_properties) | context-schema's properties (schema + per-slot validation) output. | <pre>map(object({<br/>    required         = bool<br/>    min_length       = number<br/>    validation_regex = string<br/>  }))</pre> | n/a | yes |
| <a name="input_property_order"></a> [property\_order](#input\_property\_order) | context-schema's property\_order output, wired into the provider. | `list(string)` | n/a | yes |
| <a name="input_tags_value_case"></a> [tags\_value\_case](#input\_tags\_value\_case) | context-schema's tags\_value\_case output. | `string` | n/a | yes |
| <a name="input_values"></a> [values](#input\_values) | Base context values a consuming root supplies (namespace/domain/...). | `map(string)` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_rendered"></a> [rendered](#output\_rendered) | The rendered label id. |
| <a name="output_tags"></a> [tags](#output\_tags) | The rendered tag set. |
<!-- END_TF_DOCS -->
