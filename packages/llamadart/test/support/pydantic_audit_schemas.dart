// Unmodified Pydantic 2.13.4 emissions from the independent Task A audit.
// Source: audit py/gen.py; tuple[int, str] and discriminated Cat/Dog unions.
const pydanticAuditSchemas = r'''{
  "pydantic_tuple": {
    "properties": {
      "pair": {
        "maxItems": 2,
        "minItems": 2,
        "prefixItems": [
          {
            "type": "integer"
          },
          {
            "type": "string"
          }
        ],
        "title": "Pair",
        "type": "array"
      }
    },
    "required": [
      "pair"
    ],
    "title": "T",
    "type": "object"
  },
  "pydantic_discriminator": {
    "$defs": {
      "Cat": {
        "properties": {
          "pet_type": {
            "const": "cat",
            "title": "Pet Type",
            "type": "string"
          },
          "meows": {
            "title": "Meows",
            "type": "integer"
          }
        },
        "required": [
          "pet_type",
          "meows"
        ],
        "title": "Cat",
        "type": "object"
      },
      "Dog": {
        "properties": {
          "pet_type": {
            "const": "dog",
            "title": "Pet Type",
            "type": "string"
          },
          "barks": {
            "title": "Barks",
            "type": "number"
          }
        },
        "required": [
          "pet_type",
          "barks"
        ],
        "title": "Dog",
        "type": "object"
      }
    },
    "properties": {
      "pet": {
        "discriminator": {
          "mapping": {
            "cat": "#/$defs/Cat",
            "dog": "#/$defs/Dog"
          },
          "propertyName": "pet_type"
        },
        "oneOf": [
          {
            "$ref": "#/$defs/Cat"
          },
          {
            "$ref": "#/$defs/Dog"
          }
        ],
        "title": "Pet"
      }
    },
    "required": [
      "pet"
    ],
    "title": "P",
    "type": "object"
  }
}''';
