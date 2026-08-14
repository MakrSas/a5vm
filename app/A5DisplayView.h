//
//  A5DisplayView.h
//  Вывод гостевого экрана и преобразование касаний в координаты гостя.
//
//  Кадр показывается через layer.contents: Core Animation сама вписывает
//  изображение в границы с сохранением пропорций, так что рисовать в
//  drawRect: и гонять пиксели через CPU не нужно.
//

#import <UIKit/UIKit.h>

@interface A5DisplayView : UIView

/// Текущий кадр.  View удерживает изображение до следующего кадра.
- (void)setFrameImage:(CGImageRef)image;

/// Размер гостевого экрана в пикселях; CGSizeZero, пока кадров не было.
@property (nonatomic, assign, readonly) CGSize guestSize;

/// Переводит точку из координат view в пиксели гостя с учётом полей,
/// которые появляются при вписывании по пропорциям.  Возвращает NO, если
/// касание пришлось на поле, а не на изображение.
- (BOOL)guestPoint:(CGPoint *)guestPoint forViewPoint:(CGPoint)viewPoint;

@end
