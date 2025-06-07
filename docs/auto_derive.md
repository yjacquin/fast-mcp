# AutoDerive: Automatic Tool Generation

FastMCP's AutoDerive feature provides three main capabilities:
1. Creates adapter classes for ActiveRecord models that provide standard database operations
2. Allows exposing model methods as MCP tools through lightweight annotations
3. Enables exposing controller actions as MCP tools through similar annotations

## Key Benefits

- **Reduce Boilerplate**: No need to write dedicated tool classes for common operations
- **Maintain DRY Code**: Single source of truth for your business logic
- **Simple to Use**: Just add a few annotations to your existing code
- **Automatic Registration**: Tools are automatically discovered and registered

## AutoDerive for Models

### Basic Usage

To expose a model method, make a configuration adjustment to the initializer like so:

```ruby
FastMcp.configure do |config|
  # ...other configurations...
    auto_register_tools: true,
    read_only: true, # Disables registration of Update, Create, and Destroy adapters
    excluded_namespaces: [ # Exclude these namespaces from auto-derived tools
      "ActionText",
      "ActionMailbox",
      "ActiveStorage",
      "ActiveJob",
      "ActiveRecord::Relation"
    ]
end
```


```ruby
class Product < ApplicationRecord

  expose_to_mcp :find_by_sku, description: "Find a product by its SKU code", parameters: { sku: { type: :string, description: "The SKU code to search for" } }
  expose_to_mcp :mark_as_featured, description: "Mark a product as featured", read_only: false, finder_key: :id, parameters: { featured_until: { type: :string, description: "Date until product should be featured (optional)", required: false } }

  def self.find_by_sku(sku)
    find_by(sku: sku)
  end

  def mark_as_featured(featured_until = nil)
    self.featured = true
    self.featured_until = featured_until.present? ? Date.parse(featured_until) : nil
    save
    self
  end
end
```

### Options for Model Methods

The `expose_to_mcp` method accepts the following options:

- `description` (required): A description of what the method does
- `parameters` (optional): A hash of parameter definitions
- `read_only` (optional): Whether this method modifies data (default: true)
- `finder_key` (optional): The attribute to use for finding records (default: :id)
- `tool_name` (optional): Custom name for the tool (default: `model_name_method_name`)

### MCP Tool Annotations Support

You can add MCP tool annotations to your auto-derived tools to provide additional context about their behavior:

```ruby
class Order < ApplicationRecord
  include FastMcp::AutoDerive

  expose_to_mcp :find_by_reference,
                description: "Find an order by its reference number",
                title: "Find Order",          # User-friendly title
                idempotent: true,             # Same result for repeated calls
                open_world: false,            # Doesn't interact with external systems
                parameters: {
                  reference: { type: :string, description: "The order reference number" }
                }

  expose_to_mcp :cancel,
                description: "Cancel an order",
                read_only: false,
                title: "Cancel Order",
                destructive: true,            # Performs a destructive update
                idempotent: true,             # Canceling twice has same effect
                open_world: false,            # Doesn't interact with external systems
                finder_key: :id,
                parameters: {
                  reason: { type: :string, description: "Reason for cancellation", required: false }
                }

  def self.find_by_reference(reference)
    find_by(reference_number: reference)
  end

  def cancel(reason = nil)
    self.status = 'cancelled'
    self.cancellation_reason = reason if reason.present?
    save
    self
  end
end
```

### Annotation Options

The following annotation options are available:

- `title` (optional): A human-readable title for the tool (useful for UI display)
- `destructive` (optional): If true, the tool performs destructive updates (default: !read_only)
- `idempotent` (optional): If true, calling the tool repeatedly with the same arguments has the same effect as being called once (default: false)
- `open_world` (optional): If true, the tool interacts with external systems (default: true)

## AutoDerive for Controllers

To expose controller actions, include the `FastMcp::AutoDerive::ControllerAutoDeriveModule` module:

```ruby
class ProductsController < ApplicationController
  include FastMcp::AutoDerive::ControllerAutoDeriveModule

  expose_action_to_mcp :search,
                       description: "Search for products",
                       parameters: {
                         query: { type: :string, description: "Search query" },
                         category: { type: :string, description: "Category filter", required: false }
                       }

  def search
    @products = Product.where("name LIKE ?", "%#{params[:query]}%")
    @products = @products.where(category: params[:category]) if params[:category].present?
    render json: @products
  end
end
```

### Options for Controller Actions

The `expose_action_to_mcp` method accepts the following options:

- `description` (required): A description of what the action does
- `parameters` (optional): A hash of parameter definitions
- `read_only` (optional): Whether this action modifies data (default: true)
- `tool_name` (optional): Custom name for the tool (default: `controller_name_without_controller_action_name`)
- `title` (optional): A human-readable title for the tool
- `destructive` (optional): If true, the tool performs destructive updates (default: !read_only)
- `idempotent` (optional): If true, calling the tool repeatedly has the same effect (default: false)
- `open_world` (optional): If true, the tool interacts with external systems (default: true)

### Controller Actions with Annotations

You can add MCP tool annotations to controller actions to improve LLM understanding and decision-making:

```ruby
class OrdersController < ApplicationController
  include FastMcp::AutoDerive::ControllerAutoDeriveModule

  expose_action_to_mcp :track,
                       description: "Track an order's shipping status",
                       title: "Track Order",
                       idempotent: true,
                       open_world: true,  # Connects to external shipping APIs
                       parameters: {
                         order_number: { type: :string, description: "Order number to track" }
                       }

  expose_action_to_mcp :refund,
                       description: "Process a refund for an order",
                       read_only: false,
                       title: "Refund Order",
                       destructive: true,
                       idempotent: true,  # Refunding twice has same effect
                       open_world: true,  # Connects to payment processor
                       parameters: {
                         order_id: { type: :string, description: "Order ID to refund" },
                         amount: { type: :float, description: "Amount to refund", required: false },
                         reason: { type: :string, description: "Reason for refund", required: false }
                       }

  def track
    order = Order.find_by(order_number: params[:order_number])
    if order
      tracking_info = ShippingService.get_tracking(order.tracking_number)
      render json: tracking_info
    else
      render json: { error: "Order not found" }, status: :not_found
    end
  end

  def refund
    order = Order.find(params[:order_id])
    amount = params[:amount] || order.total_amount

    result = PaymentService.process_refund(order, amount, params[:reason])

    if result[:success]
      order.update(refunded_at: Time.current, refund_amount: amount,
                  refund_reason: params[:reason])
      render json: { success: true, message: "Refund processed" }
    else
      render json: { error: result[:message] }, status: :unprocessable_entity
    end
  end
end
```

## Built-in ActiveRecord Adapters

AutoDerive automatically creates adapter classes for ActiveRecord models that provide standard database operations:

- `model_name_find`: Find a record by ID
- `model_name_where`: Find records by attributes
- `model_name_create`: Create a record
- `model_name_update`: Update a record
- `model_name_destroy`: Destroy a record
- `model_name_random`: Get a random set of records

These adapters are created automatically for each ActiveRecord model and can be disabled by setting `read_only: true` in the configuration.

## Advanced Usage

### Custom Tool Names

You can customize the tool name by providing the `tool_name` option:

```ruby
expose_to_mcp :calculate_price,
              tool_name: "get_product_price",
              description: "Calculate the price with applicable discounts",
              parameters: {
                quantity: { type: :integer, description: "Quantity to purchase" }
              }
```

## Schema Validation

When auto-deriving tools, make sure all parameters have descriptions. The schema validation requires descriptions for all parameters to work correctly. In your parameter definitions, always include a `:description` key:

```ruby
parameters: {
  name: {
    type: :string,
    description: "The name of the user",
    required: true
  }
}
```
Without descriptions, the schema validation might fail or produce incorrect results.

## How It Works

AutoDerive works through several key components:

1. **BaseAdapter**: Provides core functionality for all derived tools, including:
   - Parameter validation and schema generation
   - Error handling
   - Result serialization
   - Annotation support (readOnly, destructive, idempotent, openWorld)

2. **AutoDeriveAdapter**: Creates adapter classes for ActiveRecord models that provide standard database operations (find, where, create, update, destroy, random)

3. **ModelMethodAdapter**: Handles exposing model methods as tools by:
   - Processing method metadata and parameters
   - Creating adapter classes that wrap the methods
   - Supporting finder keys for instance methods
   - Handling parameter validation and type conversion

4. **ControllerMethodAdapter**: Similar to ModelMethodAdapter but for controller actions

During application initialization, the system:
1. Scans all models and controllers via the AST
2. Creates appropriate adapter classes for ActiveRecord models
3. Finds methods/actions that have been exposed with annotations
4. Creates adapter classes that wrap these methods as MCP tools
5. Registers these tools with the MCP server

This approach ensures that your business logic remains in your models and controllers, while making it accessible to AI agents through the Model Context Protocol.

## Best Practices

- Expose only methods that make sense for AI agent interaction
- Provide clear, detailed descriptions for methods and parameters
- Use read-only: false only for methods that change data
- Include parameter type information for better AI agent understanding
