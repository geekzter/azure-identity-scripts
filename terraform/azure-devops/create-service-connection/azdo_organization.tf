locals {
  azdo_organization_id         = var.azdo_organization_id != null && var.azdo_organization_id != "" ? var.azdo_organization_id : jsondecode(data.http.azdo_organization.response_body).value[0].id
}
data http azdo_organization {
  url                          = "${local.azdo_organization_url}/_apis/projectCollections?api-version=7.1-preview.1"

  request_headers = {
    Accept                     = "application/json"
    Authorization              = "Bearer ${data.external.azdo_token.result.accessToken}"
  }

  lifecycle {
    postcondition {
      condition                = tonumber(self.status_code) < 300
      error_message            = "Could not retrieve member information"
    }
    postcondition {
      condition                = length(jsondecode(self.response_body).value) == 1
      error_message            = "${length(jsondecode(self.response_body).value)} project collections found, 1 expected"
    }
  }
}
