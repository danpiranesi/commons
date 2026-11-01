module HomeHelper
  def forum_icon
    tag.svg(width: 32, height: 32, viewBox: "0 0 24 24", fill: "none", xmlns: "http://www.w3.org/2000/svg", "aria-hidden": true) do
      safe_join([
        tag.path(d: "M21 15C21 15.5304 20.7893 16.0391 20.4142 16.4142C20.0391 16.7893 19.5304 17 19 17H7L3 21V5C3 4.46957 3.21071 3.96086 3.58579 3.58579C3.96086 3.21071 4.46957 3 5 3H19C19.5304 3 20.0391 3.21071 20.4142 3.58579C20.7893 3.96086 21 4.46957 21 5V15Z", stroke: "currentColor", "stroke-width": 1.5, "stroke-linecap": "round", "stroke-linejoin": "round")
      ])
    end
  end

  def bookings_icon
    tag.svg(width: 32, height: 32, viewBox: "0 0 24 24", fill: "none", xmlns: "http://www.w3.org/2000/svg", "aria-hidden": true) do
      safe_join([
        tag.rect(x: 3, y: 4, width: 18, height: 18, rx: 2, stroke: "currentColor", "stroke-width": 1.5),
        tag.path(d: "M16 2V6", stroke: "currentColor", "stroke-width": 1.5, "stroke-linecap": "round"),
        tag.path(d: "M8 2V6", stroke: "currentColor", "stroke-width": 1.5, "stroke-linecap": "round"),
        tag.path(d: "M3 10H21", stroke: "currentColor", "stroke-width": 1.5)
      ])
    end
  end

  def intranet_icon
    tag.svg(width: 32, height: 32, viewBox: "0 0 24 24", fill: "none", xmlns: "http://www.w3.org/2000/svg", "aria-hidden": true) do
      safe_join([
        tag.path(d: "M14 2H6C5.46957 2 4.96086 2.21071 4.58579 2.58579C4.21071 2.96086 4 3.46957 4 4V20C4 20.5304 4.21071 21.0391 4.58579 21.4142C4.96086 21.7893 5.46957 22 6 22H18C18.5304 22 19.0391 21.7893 19.4142 21.4142C19.7893 21.0391 20 20.5304 20 20V8L14 2Z", stroke: "currentColor", "stroke-width": 1.5, "stroke-linecap": "round", "stroke-linejoin": "round"),
        tag.path(d: "M14 2V8H20", stroke: "currentColor", "stroke-width": 1.5, "stroke-linecap": "round", "stroke-linejoin": "round"),
        tag.path(d: "M12 18V12", stroke: "currentColor", "stroke-width": 1.5, "stroke-linecap": "round"),
        tag.path(d: "M9 15H15", stroke: "currentColor", "stroke-width": 1.5, "stroke-linecap": "round")
      ])
    end
  end
end
