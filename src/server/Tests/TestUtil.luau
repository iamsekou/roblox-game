-- Minimal assertions for the NAU unit tests.
local T = {}

function T.eq(actual: any, expected: any, message: string?)
	if actual ~= expected then
		error(
			string.format(
				"%sexpected %s, got %s",
				if message then message .. ": " else "",
				tostring(expected),
				tostring(actual)
			),
			2
		)
	end
end

function T.truthy(value: any, message: string?)
	if not value then
		error(message or "expected a truthy value", 2)
	end
end

return T
