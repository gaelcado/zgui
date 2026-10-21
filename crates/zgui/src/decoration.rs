//! Optional detailed paint styles; ordinary quads keep their existing fast path.
use crate::{
    canvas::{Brush, GradientStop},
    scene::{BoxShadow, Insets},
};
use std::sync::Arc;
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Corners {
    pub top_left: f32,
    pub top_right: f32,
    pub bottom_right: f32,
    pub bottom_left: f32,
}
impl Corners {
    pub fn all(radius: f32) -> Self {
        Self {
            top_left: radius,
            top_right: radius,
            bottom_right: radius,
            bottom_left: radius,
        }
    }
}
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub enum BorderStyle {
    #[default]
    Solid,
    Dashed {
        length: f32,
        gap: f32,
    },
}
#[derive(Clone, Debug, PartialEq)]
pub enum Background {
    Brush(Brush),
    /// Angle in clockwise radians; endpoints span the allocated box.
    Linear {
        angle: f32,
        stops: Arc<[GradientStop]>,
    },
    /// An image filling the box as `fit` places it (centred; CSS
    /// `background-size` cover/contain, `object-fit` alike), over the
    /// box's `fill` colour, cut to its rounded corners, under its border
    /// and children.
    Image {
        image: Arc<crate::image::ImageData>,
        fit: crate::style::ObjectFit,
    },
}
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Decoration {
    pub background: Option<Background>,
    pub corners: Option<Corners>,
    pub border_widths: Option<Insets>,
    pub border_style: BorderStyle,
    /// Some(empty) explicitly clears all shadows; None inherits the legacy shadow.
    pub shadows: Option<Arc<[BoxShadow]>>,
}
