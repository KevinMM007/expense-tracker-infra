# ---------------------------------------------------------------------------
# API Gateway HTTP API in front of the Lambda function.
#
# HTTP API is the v2 product: cheaper, faster and simpler than REST API.
# We use a single AWS_PROXY integration that hands every request straight
# to Lambda - FastAPI does the routing inside the function.
# ---------------------------------------------------------------------------

resource "aws_apigatewayv2_api" "main" {
  name          = "${local.name_prefix}-http-api"
  protocol_type = "HTTP"
  description   = "Public HTTPS entry point for the Expense Tracker Lambda."

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST", "PATCH", "DELETE", "OPTIONS"]
    allow_headers = ["Authorization", "Content-Type"]
    max_age       = 3600
  }

  tags = {
    Name = "${local.name_prefix}-http-api"
  }
}

# AWS_PROXY integration forwards the entire request envelope (method,
# headers, body, path) to Lambda. Mangum on the Lambda side translates
# the API Gateway v2 event into ASGI and back.
resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.api.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

# Two catch-all routes: one for the root path "/" and one for everything
# else. {proxy+} requires at least one path segment, so without the root
# route GET / would 404 before even reaching Lambda.
resource "aws_apigatewayv2_route" "root" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "ANY /"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_route" "proxy" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "ANY /{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

# $default stage with auto_deploy = true means every change to routes or
# integrations goes live the moment terraform apply finishes. Saves us
# from having to manage stage deployments by hand for a portfolio project.
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = "$default"
  auto_deploy = true

  tags = {
    Name = "${local.name_prefix}-http-api-default"
  }
}

# Without this, every request through API Gateway returns 500 because
# API Gateway isn't authorised to call lambda:InvokeFunction.
resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "apigateway.amazonaws.com"

  # Scope down to this specific API; if we ever create a second API later,
  # it won't accidentally inherit permission to invoke this Lambda.
  source_arn = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}
