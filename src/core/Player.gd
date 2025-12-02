class_name Player

# Player configuration
var id: int = -1
var color: Color = Color.WHITE
var target: Vector2i = Vector2i.ZERO

# Player state
var flow_field: FlowField = null
var units: Array = []
var resources: int = 0