locals {
  azdo_api_version             = "7.1-preview.1"
}

data http azdo_service_connection {
  url                          = "${local.azdo_organization_url}/${var.azdo_project_name}/_apis/serviceendpoint/endpoints/${module.service_connection.service_connection_id}?${local.azdo_api_version}"
  request_headers = {
    Accept                     = "application/json"
    Authorization              = "Bearer ${data.external.azdo_token.result.accessToken}"
  }

  lifecycle {
    postcondition {
      condition                = tonumber(self.status_code) < 300
      error_message            = "Could not retrieve account information from ${self.url}"
    }
    postcondition {
      condition                = can(jsondecode(self.response_body).authorization.parameters.workloadIdentityFederationIssuer)
      error_message            = "Issuer not returned from ${self.url}, or not in expected format"
    }
    postcondition {
      condition                = can(jsondecode(self.response_body).authorization.parameters.workloadIdentityFederationSubject)
      error_message            = "Federated subject not returned from ${self.url}, or not in expected format"
    }
  }
}