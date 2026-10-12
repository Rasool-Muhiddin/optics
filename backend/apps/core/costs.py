"""
Cost visibility. Purchase prices, average costs and profit are only sent to owners and to
staff with `LabUser.can_view_costs` (`lab_user.sees_costs`). Fields are removed from the
serializer itself, so they are neither rendered nor accepted on write.
"""


def request_sees_costs(request):
    lab_user = getattr(request, "lab_user", None)
    return bool(lab_user and lab_user.sees_costs)


class CostFieldsMixin:
    """Serializer mixin: list the sensitive fields in `cost_fields`."""

    cost_fields = ()

    def get_fields(self):
        fields = super().get_fields()
        if not request_sees_costs(self.context.get("request")):
            for name in self.cost_fields:
                fields.pop(name, None)
        return fields


class CostOutputMixin:
    """
    Serializer mixin for write forms where staff may *enter* a cost (e.g. the purchase cost
    of a stock entry or a supplier order line) but must not *see* costs: the fields listed
    in `output_cost_fields` are accepted on write and dropped from the response.
    """

    output_cost_fields = ()

    def to_representation(self, instance):
        data = super().to_representation(instance)
        if not request_sees_costs(self.context.get("request")):
            for name in self.output_cost_fields:
                data.pop(name, None)
        return data
