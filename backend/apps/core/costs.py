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
